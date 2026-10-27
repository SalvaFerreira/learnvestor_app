import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const HERE = dirname(fileURLToPath(import.meta.url));
const SUPABASE = join(HERE, '..', '..', 'supabase');

const sqlFiles = (dir) =>
  readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({ name: f, sql: readFileSync(join(dir, f), 'utf8') }));

/** Fresh database with every migration and seed applied, as `supabase db reset` would. */
export async function createDb() {
  const db = await PGlite.create();
  await db.exec(readFileSync(join(HERE, 'supabase-stub.sql'), 'utf8'));
  for (const file of [...sqlFiles(join(SUPABASE, 'migrations')), ...sqlFiles(join(SUPABASE, 'seeds'))]) {
    try {
      await db.exec(file.sql);
    } catch (error) {
      throw new Error(`${file.name}: ${error.message}`);
    }
  }
  return db;
}

/** Simulates a Supabase anonymous sign-in (no email; fires the on_auth_user_created trigger). */
export async function createUser(db, meta = {}) {
  const { rows } = await db.query(
    'insert into auth.users (is_anonymous, raw_user_meta_data) values (true, $1) returning id',
    [JSON.stringify(meta)],
  );
  return rows[0].id;
}

/**
 * Runs `fn(q)` inside a transaction as an API role, like PostgREST does.
 * `q(sql, params)` returns rows. Pass uid = null for the anon role.
 */
export async function as(db, uid, fn, role = uid ? 'authenticated' : 'anon') {
  return db.transaction(async (tx) => {
    await tx.query("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify(uid ? { sub: uid, role } : { role }),
    ]);
    await tx.exec(`set local role ${role}`);
    const q = async (sql, params = []) => (await tx.query(sql, params)).rows;
    return fn(q);
  });
}

/** Calls an RPC as the given user and returns its JSON result. */
export async function rpc(db, uid, fn, args = {}) {
  const names = Object.keys(args);
  const call = `select public.${fn}(${names.map((n, i) => `${n} => $${i + 1}`).join(', ')}) as result`;
  return as(db, uid, async (q) => (await q(call, Object.values(args)))[0].result);
}

/** Superuser query (test setup only, e.g. moving timestamps back in time). */
export async function sql(db, text, params = []) {
  return (await db.query(text, params)).rows;
}

/** Completes onboarding with sensible defaults. */
export async function onboard(db, uid, username) {
  return rpc(db, uid, 'complete_onboarding', {
    p_username: username,
    p_age_bracket: '18-24',
    p_daily_goal_xp: 30,
    p_country_code: 'PT',
    p_terms_version: '2026-10',
  });
}

/** Builds the all-correct answers object from a start_lesson payload. */
export function correctAnswers(lesson) {
  return Object.fromEntries(lesson.exercises.filter((e) => 'answer' in e).map((e) => [e.id, e.answer]));
}

/** Pretends the attempt started `seconds` ago (complete_lesson rejects impossibly fast attempts). */
export async function backdateAttempt(db, attemptId, seconds = 120) {
  await sql(db, `update public.lesson_attempts set started_at = now() - make_interval(secs => $2) where id = $1`, [
    attemptId,
    seconds,
  ]);
}

/** Starts and finishes a lesson with every answer correct. */
export async function passLesson(db, uid, lessonId) {
  const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: lessonId, p_locale: 'en' });
  await backdateAttempt(db, lesson.attempt_id);
  return rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: correctAnswers(lesson) });
}
