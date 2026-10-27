import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { applySql } from './db.mjs';

export * from './db.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SUPABASE = join(HERE, '..', '..', 'supabase');

const sqlFiles = (dir) =>
  readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({ name: f, sql: readFileSync(join(dir, f), 'utf8') }));

/** The Supabase stand-in, every migration and every seed, in the order they are applied. */
export function schemaFiles() {
  return [
    { name: 'supabase-stub.sql', sql: readFileSync(join(HERE, 'supabase-stub.sql'), 'utf8') },
    ...sqlFiles(join(SUPABASE, 'migrations')),
    ...sqlFiles(join(SUPABASE, 'seeds')),
  ];
}

/** Fresh database with every migration and seed applied, as `supabase db reset` would. */
export async function createDb() {
  const db = await PGlite.create();
  await applySql(db, schemaFiles());
  return db;
}
