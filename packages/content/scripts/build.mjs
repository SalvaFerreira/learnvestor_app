// Validates all content and compiles it to supabase/seeds/10_content.sql (local/dev seeds,
// drafts included).
//
//   node scripts/build.mjs           write the SQL
//   node scripts/build.mjs --check   fail if content is invalid or the SQL is out of date (CI)

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { relative } from 'node:path';
import { compileSql, coverage, loadContent, SEED_PATH, validateContent } from './lib/content.mjs';

const content = loadContent();
const errors = validateContent(content);
if (errors.length) {
  console.error(`Content is invalid (${errors.length} problem${errors.length > 1 ? 's' : ''}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

const output = compileSql(content);
const totals = coverage(content).reduce((t, r) => ({ planned: t.planned + r.planned, draft: t.draft + r.draft, reviewed: t.reviewed + r.reviewed }), { planned: 0, draft: 0, reviewed: 0 });
const summary = `${content.lessons.length} lessons (${totals.reviewed} reviewed, ${totals.draft} draft, ${totals.planned} still planned), ${content.achievements.length} achievements, ${content.instruments.length} instruments.`;

if (process.argv.includes('--check')) {
  const current = existsSync(SEED_PATH) ? readFileSync(SEED_PATH, 'utf8') : '';
  if (current !== output) {
    console.error(`${relative(process.cwd(), SEED_PATH)} is out of date. Run: npm run build (in packages/content)`);
    process.exit(1);
  }
  console.log(`Content OK: ${summary}`);
} else {
  writeFileSync(SEED_PATH, output);
  console.log(`Wrote ${relative(process.cwd(), SEED_PATH)}: ${summary}`);
}
