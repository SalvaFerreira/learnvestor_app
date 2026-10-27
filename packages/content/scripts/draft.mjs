// Drafts lessons from curriculum.yaml with Claude. Every draft is written with
// status "draft": a person must check the facts against the listed sources, set
// status "reviewed" + review {by, date}, and only then is it published.
//
//   npm run draft -- <lesson-id> [<lesson-id> ...]     specific lessons
//   npm run draft -- --unit <unit-id>                  every planned lesson of a unit
//   npm run draft -- --next 5                          the next 5 planned lessons
//   add --force to redraft a lesson that already has a file, --dry-run to only print the prompt
//
// Needs Anthropic credentials (ANTHROPIC_API_KEY or an `ant auth login` profile).

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import Anthropic from '@anthropic-ai/sdk';
import { coverage, LESSONS_DIR, loadContent, loadSchema, validateContent } from './lib/content.mjs';

const MODEL = 'claude-opus-5-5';
const MAX_REPAIRS = 2;

// ---- what to draft -------------------------------------------------------------------------

const args = process.argv.slice(2);
const force = args.includes('--force');
const content = loadContent();
const existing = new Set(content.lessons.map(({ data }) => data.id));
let targets;
if (args.includes('--unit')) {
  const unitId = args[args.indexOf('--unit') + 1];
  targets = [...content.planned.values()].filter((e) => e.unit.id === unitId).map((e) => e.id);
} else if (args.includes('--next')) {
  const n = Number(args[args.indexOf('--next') + 1] ?? 5);
  targets = coverage(content).flatMap((r) => r.next).slice(0, n);
} else {
  targets = args.filter((a) => !a.startsWith('--'));
}
targets = targets.filter((id) => force || !existing.has(id));
for (const id of targets) {
  if (!content.planned.has(id)) {
    console.error(`${id} is not in curriculum.yaml`);
    process.exit(1);
  }
}
if (!targets.length) {
  console.log('Nothing to draft (use --force to redraft existing lessons).');
  process.exit(0);
}

// ---- structured output schema --------------------------------------------------------------

// The API accepts a subset of JSON Schema: no numeric/length constraints or patterns, anyOf
// instead of oneOf, $defs instead of definitions. Those rules are re-checked locally anyway.
const DROP = new Set(['$schema', '$id', 'minimum', 'maximum', 'minLength', 'maxLength', 'minItems', 'maxItems', 'pattern']);
function toApiSchema(node) {
  if (Array.isArray(node)) return node.map(toApiSchema);
  if (!node || typeof node !== 'object') return node;
  const out = {};
  for (const [key, value] of Object.entries(node)) {
    if (DROP.has(key)) continue;
    if (key === '$ref') out.$ref = value.replace('#/definitions/', '#/$defs/');
    else if (key === 'oneOf') out.anyOf = toApiSchema(value);
    else if (key === 'definitions') out.$defs = toApiSchema(value);
    else out[key] = toApiSchema(value);
  }
  return out;
}

const lessonSchema = loadSchema();
const DRAFT_SCHEMA = toApiSchema({
  type: 'object',
  additionalProperties: false,
  required: ['title', 'description', 'exercises'],
  properties: {
    title: lessonSchema.properties.title,
    description: lessonSchema.properties.description,
    exercises: lessonSchema.properties.exercises,
  },
  definitions: lessonSchema.definitions,
});

// ---- prompts -------------------------------------------------------------------------------

const example = readFileSync(join(LESSONS_DIR, 'banks', 'compound-interest.json'), 'utf8');

// Stable across every call (cached): style guide + format + one full example.
const SYSTEM = `You write lessons for LearnVestor, a gamified financial-literacy app (like Duolingo) launching in Portugal. Learners are beginners aged 16+, on a phone, a few minutes per lesson.

Write every text field in European Portuguese (pt, PT-PT, "tu" form, Portuguese spelling and vocabulary: "ação", "carteira", "poupança", "telemóvel", euros) and natural English (en). The English is a faithful translation, not a different lesson.

Lesson shape:
- Start with one short "info" card (2-4 sentences) that teaches the core idea. A second info card is allowed midway for longer topics.
- Then 4 to 6 graded exercises that check exactly the lesson goals. Mix types: multiple_choice, true_false, fill_blank, order, match (3-5 term/definition pairs), numeric (a small calculation with euros, answer already rounded to "decimals").
- Put the correct option FIRST in options; list order items and match pairs in the CORRECT order. The app shuffles them.
- Wrong options must be plausible but clearly wrong for someone who read the info card. No trick questions, no "all of the above".
- Every graded exercise has an explanation (1-2 sentences) that teaches, not just repeats the answer.
- fill_blank sentences contain exactly one "___".
- Keep texts short: prompts under 160 characters, options under 80.
- Exercise ids are short kebab-case and unique within the lesson.

Content rules:
- Educational only. Never recommend a specific product, bank, broker, fund or security, and never tell the learner what to buy.
- Teach the facts given for the lesson exactly. If a rule is time-sensitive (tax rates, limits), say it refers to the rules in force and point to the official source by name, without inventing numbers that were not provided.
- Use Portuguese context where it helps (IRS, Segurança Social, Banco de Portugal, CMVM, Certificados de Aforro) while keeping the English version understandable to non-Portuguese readers.

Reply with the lesson's title, description and exercises only, as JSON matching the schema. Example of a complete lesson file (you only produce title, description and exercises):

${example}`;

function lessonPrompt(entry) {
  const sources = (entry.sources ?? []).map((s) => content.curriculum.sources[s] ?? s);
  const siblings = entry.unit.lessons.map((l) => `${l.id === entry.id ? '→ ' : '  '}${l.title.pt}`).join('\n');
  return [
    `Track: ${entry.track.title.pt} / ${entry.track.title.en}`,
    `Unit: ${entry.unit.title.pt}: ${entry.unit.description.pt}`,
    `Lessons in this unit (avoid repeating the others):\n${siblings}`,
    `Lesson: ${entry.title.pt} / ${entry.title.en}`,
    `Goals:\n${entry.goals.map((g) => `- ${g}`).join('\n')}`,
    entry.facts?.length ? `Facts that must be taught exactly:\n${entry.facts.map((f) => `- ${f}`).join('\n')}` : '',
    entry.regions ? `Audience: ${entry.regions.join(', ')} only.` : 'Audience: everyone (keep it valid outside Portugal too).',
    sources.length ? `Reference sources (the reviewer will check against them): ${sources.join(', ')}` : '',
    `Use these titles: pt "${entry.title.pt}", en "${entry.title.en}".`,
  ].filter(Boolean).join('\n\n');
}

// Rewards grow with the track and the unit, so later lessons are worth more.
const BASE_XP = { banks: 20, taxes: 25, investment: 30, mindset: 25, advanced: 40 };
function rewardsFor(entry) {
  const xp = Math.min(60, (BASE_XP[entry.track.id] ?? 25) + 5 * (entry.unit.position - 1));
  return { xp, coins: Math.round((xp * 1.5) / 5) * 5 };
}

// ---- drafting ------------------------------------------------------------------------------

if (args.includes('--dry-run')) {
  console.log(`Would draft: ${targets.join(', ')}\n\n--- prompt for ${targets[0]} ---\n${lessonPrompt(content.planned.get(targets[0]))}`);
  console.log(`\n--- rewards ---\n${JSON.stringify(rewardsFor(content.planned.get(targets[0])))}`);
  console.log(`\n--- output schema: ${JSON.stringify(DRAFT_SCHEMA).length} chars, $defs: ${Object.keys(DRAFT_SCHEMA.$defs).join(', ')}`);
  process.exit(0);
}

const client = new Anthropic();

async function ask(messages) {
  const stream = client.beta.messages.stream({
    model: MODEL,
    max_tokens: 32000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    thinking: { type: 'adaptive' },
    output_config: { effort: 'high', format: { type: 'json_schema', schema: DRAFT_SCHEMA } },
    system: [{ type: 'text', text: SYSTEM, cache_control: { type: 'ephemeral' } }],
    messages,
  });
  const message = await stream.finalMessage();
  if (message.stop_reason === 'refusal') throw new Error(`refused (${message.stop_details?.category ?? 'no category'})`);
  if (message.stop_reason === 'max_tokens') throw new Error('response hit max_tokens');
  const text = message.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
  const cached = message.usage.cache_read_input_tokens ?? 0;
  return { message, body: JSON.parse(text), cached };
}

async function draft(entry) {
  const messages = [{ role: 'user', content: lessonPrompt(entry) }];
  for (let attempt = 0; attempt <= MAX_REPAIRS; attempt++) {
    const { message, body, cached } = await ask(messages);
    const lesson = {
      id: entry.id,
      version: 1,
      unit: entry.unit.id,
      status: 'draft',
      sources: entry.sources ?? [],
      ...(entry.valid_until ?? entry.track.valid_until ? { valid_until: String(entry.valid_until ?? entry.track.valid_until) } : {}),
      ...rewardsFor(entry),
      ...body,
    };
    const file = join('content', 'lessons', entry.track.id, `${entry.id}.json`);
    const errors = validateContent({ ...content, lessons: [{ file, data: lesson }], achievements: [] }).filter((e) => e.startsWith(file));
    if (!errors.length) return { lesson, cached };
    console.warn(`  ${entry.id}: ${errors.length} problem(s), asking for a fix`);
    messages.push({ role: 'assistant', content: message.content });
    messages.push({ role: 'user', content: `The lesson has these problems:\n- ${errors.join('\n- ')}\nReturn the full corrected lesson.` });
  }
  throw new Error('still invalid after repairs');
}

let failures = 0;
for (const id of targets) {
  const entry = content.planned.get(id);
  process.stdout.write(`Drafting ${id}... `);
  try {
    const { lesson, cached } = await draft(entry);
    const dir = join(LESSONS_DIR, entry.track.id);
    mkdirSync(dir, { recursive: true });
    const path = join(dir, `${id}.json`);
    if (existsSync(path) && !force) throw new Error('file appeared meanwhile');
    writeFileSync(path, `${JSON.stringify(lesson, null, 2)}\n`);
    console.log(`ok (${lesson.exercises.length} exercises${cached ? ', cache hit' : ''})`);
  } catch (error) {
    failures++;
    if (error instanceof Anthropic.RateLimitError) console.log('rate limited, try again later');
    else if (error instanceof Anthropic.APIError) console.log(`API error ${error.status}: ${error.message}`);
    else console.log(`failed: ${error.message}`);
  }
}
console.log(`\nDone. Review the new drafts, then run npm run build.${failures ? ` ${failures} failed.` : ''}`);
process.exitCode = failures ? 1 : 0;
