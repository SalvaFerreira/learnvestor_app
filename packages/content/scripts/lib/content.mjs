// Loads, validates and compiles LearnVestor content. Used by build, publish, status and
// draft scripts so they all apply exactly the same rules.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import { parse as parseYaml } from 'yaml';

export const LOCALES = ['en', 'pt'];
export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const CONTENT_DIR = join(ROOT, 'content');
export const LESSONS_DIR = join(CONTENT_DIR, 'lessons');
export const SEED_PATH = join(ROOT, '..', '..', 'supabase', 'seeds', '10_content.sql');

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));

export function loadSchema() {
  return readJson(join(ROOT, 'schema', 'lesson.schema.json'));
}

/** Curriculum + lesson files, with every planned lesson resolved to its track and unit. */
export function loadContent() {
  const curriculum = parseYaml(readFileSync(join(CONTENT_DIR, 'curriculum.yaml'), 'utf8'));
  const files = readdirSync(LESSONS_DIR, { recursive: true })
    .filter((f) => f.endsWith('.json'))
    .map((f) => join(LESSONS_DIR, f))
    .sort();
  const lessons = files.map((file) => ({ file: relative(ROOT, file).replaceAll('\\', '/'), data: readJson(file) }));

  // planned lessons in curriculum order, with derived position, regions and premium
  const planned = new Map();
  for (const track of curriculum.tracks) {
    track.units.forEach((unit, unitIndex) => {
      unit.position = unitIndex + 1;
      unit.lessons.forEach((entry, lessonIndex) => {
        planned.set(entry.id, {
          ...entry,
          track,
          unit,
          position: lessonIndex + 1,
          regions: entry.regions ?? track.regions ?? null,
          premium: Boolean(entry.premium),
        });
      });
    });
  }

  return {
    curriculum,
    planned,
    lessons,
    achievements: readJson(join(CONTENT_DIR, 'achievements.json')),
    instruments: readJson(join(CONTENT_DIR, 'instruments.json')),
  };
}

/** Every content problem as "where: message". Empty array = valid. */
export function validateContent(content, { today = new Date().toISOString().slice(0, 10) } = {}) {
  const { curriculum, planned, lessons, achievements } = content;
  const errors = [];
  const fail = (where, message) => errors.push(`${where}: ${message}`);
  const ajv = new Ajv({ allErrors: true });
  const validateLesson = ajv.compile(loadSchema());

  // curriculum
  const ids = new Set();
  const unique = (kind, id) => {
    if (ids.has(`${kind}:${id}`)) fail(`curriculum ${kind} ${id}`, 'duplicate id');
    ids.add(`${kind}:${id}`);
  };
  const positions = new Set();
  for (const track of curriculum.tracks) {
    unique('track', track.id);
    if (positions.has(track.position)) fail(`track ${track.id}`, `position ${track.position} is used twice`);
    positions.add(track.position);
    for (const l of LOCALES) {
      if (!track.title?.[l] || !track.description?.[l]) fail(`track ${track.id}`, `missing ${l} text`);
    }
    for (const unit of track.units) {
      unique('unit', unit.id);
      for (const l of LOCALES) {
        if (!unit.title?.[l] || !unit.description?.[l]) fail(`unit ${unit.id}`, `missing ${l} text`);
      }
      for (const entry of unit.lessons) {
        unique('lesson', entry.id);
        if (!/^[a-z0-9-]+$/.test(entry.id)) fail(`curriculum lesson ${entry.id}`, 'invalid id');
        if (!entry.title?.pt || !entry.title?.en) fail(`curriculum lesson ${entry.id}`, 'needs pt and en titles');
        if (!entry.goals?.length) fail(`curriculum lesson ${entry.id}`, 'needs at least one goal');
        for (const s of entry.sources ?? []) {
          if (!curriculum.sources?.[s] && !/^https?:\/\//.test(s)) fail(`curriculum lesson ${entry.id}`, `unknown source ${s}`);
        }
      }
    }
  }

  // lessons
  const seen = new Set();
  for (const { file, data: lesson } of lessons) {
    if (!validateLesson(lesson)) {
      for (const e of validateLesson.errors) fail(file, `${e.instancePath || '/'} ${e.message}`);
      continue;
    }
    if (seen.has(lesson.id)) fail(file, `duplicate lesson id ${lesson.id}`);
    seen.add(lesson.id);

    const entry = planned.get(lesson.id);
    if (!entry) fail(file, `lesson ${lesson.id} is not in curriculum.yaml`);
    else if (entry.unit.id !== lesson.unit) fail(file, `unit ${lesson.unit} does not match curriculum (${entry.unit.id})`);

    if (lesson.status === 'reviewed') {
      if (!lesson.review) fail(file, 'reviewed lessons need review.by and review.date');
      if (!lesson.sources?.length) fail(file, 'reviewed lessons need at least one source');
    }
    if (lesson.valid_until && lesson.valid_until < today) {
      fail(file, `content expired on ${lesson.valid_until}: re-review it, bump version and update valid_until`);
    }

    const exerciseIds = new Set();
    let graded = 0;
    for (const ex of lesson.exercises) {
      const where = `${file} exercise ${ex.id}`;
      if (exerciseIds.has(ex.id)) fail(where, 'duplicate exercise id');
      exerciseIds.add(ex.id);
      if (ex.type !== 'info') graded++;

      const lists = ex.type === 'match' ? [ex.left, ex.right] : [ex.options ?? ex.items].filter(Boolean);
      for (const list of lists) {
        const sizes = LOCALES.map((l) => list[l].length);
        if (new Set(sizes).size !== 1) fail(where, `lists differ in length between locales (${sizes})`);
        const [min, max] = ex.type === 'match' ? [3, 5] : ex.type === 'order' ? [3, 6] : [2, 6];
        if (sizes[0] < min || sizes[0] > max) fail(where, `needs between ${min} and ${max} entries`);
        for (const l of LOCALES) {
          if (new Set(list[l]).size !== list[l].length) fail(where, `duplicate text (${l})`);
        }
        if ('answer' in ex && typeof ex.answer === 'number' && ex.type !== 'numeric' && ex.answer >= sizes[0]) {
          fail(where, `answer ${ex.answer} is out of range`);
        }
      }
      if (ex.type === 'match' && ex.left.en.length !== ex.right.en.length) fail(where, 'left and right need the same size');
      if (ex.type === 'numeric') {
        const rounded = Number(ex.answer.toFixed(ex.decimals));
        if (rounded !== ex.answer) fail(where, `answer must already be rounded to ${ex.decimals} decimals`);
      }
      if (ex.type === 'fill_blank') {
        for (const l of LOCALES) {
          if ((ex.sentence[l].match(/___/g) ?? []).length !== 1) fail(where, `sentence (${l}) must contain exactly one ___`);
        }
      }
    }
    if (graded < 2) fail(file, 'a lesson needs at least 2 graded exercises');
  }

  for (const a of achievements) {
    for (const l of LOCALES) {
      if (!a.title?.[l] || !a.description?.[l]) fail(`achievement ${a.id}`, `missing ${l} text`);
    }
  }
  return errors;
}

/** Planned / draft / reviewed counts per track and unit. */
export function coverage(content) {
  const status = new Map(content.lessons.map(({ data }) => [data.id, data.status]));
  const rows = [];
  for (const track of content.curriculum.tracks) {
    for (const unit of track.units) {
      const counts = { planned: 0, draft: 0, reviewed: 0 };
      for (const entry of unit.lessons) counts[status.get(entry.id) ?? 'planned']++;
      rows.push({ track: track.id, unit: unit.id, ...counts, next: unit.lessons.filter((e) => !status.has(e.id)).map((e) => e.id) });
    }
  }
  return rows;
}

// ---- SQL ------------------------------------------------------------------------------------

const lit = (v) => (v === null || v === undefined ? 'null' : `'${String(v).replaceAll("'", "''")}'`);
const json = (v) => `${lit(JSON.stringify(v))}::jsonb`;
const textArray = (v) => (v ? `array[${v.map(lit).join(', ')}]::text[]` : 'null');
const hash = (v) => createHash('sha256').update(JSON.stringify(v)).digest('hex');

const TEXT_FIELDS = ['title', 'body', 'prompt', 'statement', 'sentence', 'explanation', 'unit'];
const LIST_FIELDS = ['options', 'items', 'left', 'right'];

/** The per-locale shape the app receives (answers are added server-side by start_lesson). */
export function compileExercise(ex, locale) {
  const out = { id: ex.id, type: ex.type };
  for (const field of TEXT_FIELDS) if (ex[field]) out[field] = ex[field][locale];
  for (const field of LIST_FIELDS) if (ex[field]) out[field] = ex[field][locale];
  if (ex.type === 'numeric') out.decimals = ex.decimals;
  return out;
}

/** Expected response per graded exercise, in the form the app submits. */
export function answerFor(ex) {
  switch (ex.type) {
    case 'multiple_choice':
    case 'fill_blank':
    case 'true_false':
    case 'numeric':
      return ex.answer;
    case 'order':
      return ex.items.en.map((_, i) => i);
    case 'match':
      return ex.left.en.map((_, i) => i);
    default:
      return undefined;
  }
}

/**
 * SQL that upserts the curriculum, lessons, achievements and instruments.
 * reviewedOnly: production publishing (drafts are left out and become unpublished).
 */
export function compileSql(content, { reviewedOnly = false } = {}) {
  const { curriculum, planned, achievements, instruments } = content;
  const lessons = content.lessons.filter(({ data }) => !reviewedOnly || data.status === 'reviewed');
  const sql = [];
  sql.push('-- GENERATED by packages/content (scripts/lib/content.mjs). Do not edit.');
  sql.push(`-- ${reviewedOnly ? 'Reviewed lessons only (production).' : 'All lessons including drafts (local/dev seeds).'}`);
  sql.push('begin;', 'set constraints all deferred;', '');

  sql.push('-- tracks & units');
  for (const t of curriculum.tracks) {
    sql.push(
      `insert into public.tracks (id, position, icon, color, is_premium) values (${lit(t.id)}, ${t.position}, ${lit(t.icon)}, ${lit(t.color)}, ${Boolean(t.premium)})\n` +
        `  on conflict (id) do update set position = excluded.position, icon = excluded.icon, color = excluded.color, is_premium = excluded.is_premium;`,
    );
    for (const l of LOCALES) {
      sql.push(
        `insert into public.track_translations (track_id, locale, title, description) values (${lit(t.id)}, ${lit(l)}, ${lit(t.title[l])}, ${lit(t.description[l])})\n` +
          `  on conflict (track_id, locale) do update set title = excluded.title, description = excluded.description;`,
      );
    }
    for (const u of t.units) {
      sql.push(
        `insert into public.units (id, track_id, position) values (${lit(u.id)}, ${lit(t.id)}, ${u.position})\n` +
          `  on conflict (id) do update set track_id = excluded.track_id, position = excluded.position;`,
      );
      for (const l of LOCALES) {
        sql.push(
          `insert into public.unit_translations (unit_id, locale, title, description) values (${lit(u.id)}, ${lit(l)}, ${lit(u.title[l])}, ${lit(u.description[l])})\n` +
            `  on conflict (unit_id, locale) do update set title = excluded.title, description = excluded.description;`,
        );
      }
    }
  }

  sql.push('', '-- lessons (versions are immutable: changing a published version without bumping it is an error)');
  for (const { data: lesson } of lessons) {
    const entry = planned.get(lesson.id);
    const contentHash = hash(lesson);
    const answerKey = Object.fromEntries(lesson.exercises.filter((e) => e.type !== 'info').map((e) => [e.id, answerFor(e)]));
    const id = lit(lesson.id);
    sql.push(
      `insert into public.lessons (id, unit_id, position, xp_reward, coin_reward, is_premium, regions) values (${id}, ${lit(lesson.unit)}, ${entry.position}, ${lesson.xp}, ${lesson.coins}, ${entry.premium}, ${textArray(entry.regions)})\n` +
        `  on conflict (id) do update set unit_id = excluded.unit_id, position = excluded.position, xp_reward = excluded.xp_reward, coin_reward = excluded.coin_reward, is_premium = excluded.is_premium, regions = excluded.regions;`,
    );
    sql.push(
      `do $$ begin\n` +
        `  if exists (select 1 from public.lesson_versions where lesson_id = ${id} and version = ${lesson.version} and content_hash <> ${lit(contentHash)}) then\n` +
        `    raise exception 'Lesson % v% changed without a version bump', ${id}, ${lesson.version};\n` +
        `  end if;\n` +
        `end $$;`,
    );
    sql.push(
      `insert into public.lesson_versions (lesson_id, version, answer_key, exercise_count, gradable_count, content_hash) values (${id}, ${lesson.version}, ${json(answerKey)}, ${lesson.exercises.length}, ${Object.keys(answerKey).length}, ${lit(contentHash)})\n` +
        `  on conflict (lesson_id, version) do nothing;`,
    );
    for (const l of LOCALES) {
      sql.push(
        `insert into public.lesson_translations (lesson_id, version, locale, title, description, exercises) values (${id}, ${lesson.version}, ${lit(l)}, ${lit(lesson.title[l])}, ${lit(lesson.description[l])}, ${json(lesson.exercises.map((e) => compileExercise(e, l)))})\n` +
          `  on conflict (lesson_id, version, locale) do nothing;`,
      );
    }
    sql.push(`update public.lessons set published_version = ${lesson.version} where id = ${id};`);
  }
  const published = lessons.map(({ data }) => lit(data.id));
  sql.push(`update public.lessons set published_version = null${published.length ? ` where id not in (${published.join(', ')})` : ''};`);

  sql.push('', '-- achievements');
  achievements.forEach((a, i) => {
    sql.push(
      `insert into public.achievements (id, metric, threshold, gem_reward, icon, position) values (${lit(a.id)}, ${lit(a.metric)}, ${a.threshold}, ${a.gems}, ${lit(a.icon)}, ${i + 1})\n` +
        `  on conflict (id) do update set metric = excluded.metric, threshold = excluded.threshold, gem_reward = excluded.gem_reward, icon = excluded.icon, position = excluded.position;`,
    );
    for (const l of LOCALES) {
      sql.push(
        `insert into public.achievement_translations (achievement_id, locale, title, description) values (${lit(a.id)}, ${lit(l)}, ${lit(a.title[l])}, ${lit(a.description[l])})\n` +
          `  on conflict (achievement_id, locale) do update set title = excluded.title, description = excluded.description;`,
      );
    }
  });

  sql.push('', '-- instruments (curated universe refreshed by market-data-sync)');
  for (const i of instruments) {
    sql.push(
      `insert into public.instruments (symbol, name, exchange, currency, sector, popularity, is_active) values (${lit(i.symbol)}, ${lit(i.name)}, ${lit(i.exchange)}, ${lit(i.currency)}, ${lit(i.sector)}, ${i.popularity}, true)\n` +
        `  on conflict (symbol) do update set name = excluded.name, exchange = excluded.exchange, currency = excluded.currency, sector = excluded.sector, popularity = excluded.popularity, is_active = true;`,
    );
  }
  sql.push(`update public.instruments set is_active = false where symbol not in (${instruments.map((i) => lit(i.symbol)).join(', ')});`);

  sql.push('', 'commit;', '');
  return sql.join('\n');
}
