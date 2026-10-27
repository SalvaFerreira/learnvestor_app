// Helpers shared by the Node tools (tests, fixtures, dev server) and the browser demo.
// No Node APIs here: this file is bundled into the web demo.

/** Applies [files] ({ name, sql } in order), as `supabase db reset` would. */
export async function applySql(db, files) {
  for (const file of files) {
    try {
      await db.exec(file.sql);
    } catch (error) {
      throw new Error(`${file.name}: ${error.message}`);
    }
  }
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
