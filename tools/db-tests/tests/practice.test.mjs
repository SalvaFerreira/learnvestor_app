// Practice mode: built from mistakes, never costs hearts, a good session returns one.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';
import { backdateAttempt, correctAnswers, createDb, createUser, onboard, passLesson, rpc, sql } from '../harness.mjs';

let db;
let n = 0;

async function learner() {
  const uid = await createUser(db);
  await onboard(db, uid, `practice${++n}`);
  return uid;
}

const backdateSession = (id) =>
  sql(db, `update public.practice_sessions set started_at = now() - interval '5 minutes' where id = $1`, [id]);

before(async () => {
  db = await createDb();
});

describe('practice', () => {
  test('needs at least one completed lesson', async () => {
    const uid = await learner();
    await assert.rejects(rpc(db, uid, 'start_practice'), /nothing_to_practice/);
  });

  test('puts past mistakes first, with unique ids and answers', async () => {
    const uid = await learner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank', p_locale: 'pt' });
    await backdateAttempt(db, lesson.attempt_id);
    const answers = correctAnswers(lesson);
    answers['deposit-guarantee'] = false;
    await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: answers });

    const practice = await rpc(db, uid, 'start_practice', { p_locale: 'pt' });
    assert.equal(practice.exercises[0].id, 'what-is-a-bank/deposit-guarantee');
    assert.equal(practice.exercises[0].answer, true);
    assert.ok(practice.exercises[0].statement.includes('UE'), 'localized');
    assert.equal(practice.exercises.length, 4); // every graded exercise of the only completed lesson
    assert.equal(new Set(practice.exercises.map((e) => e.id)).size, practice.exercises.length);
    assert.ok(practice.exercises.every((e) => e.type !== 'info'));
  });

  test('can be played with zero hearts and a good session gives one back', async () => {
    const uid = await learner();
    await passLesson(db, uid, 'what-is-a-bank');
    await sql(db, `update public.user_stats set hearts = 0, hearts_updated_at = now() where user_id = $1`, [uid]);

    const practice = await rpc(db, uid, 'start_practice');
    await backdateSession(practice.attempt_id);
    const result = await rpc(db, uid, 'complete_practice', {
      p_session_id: practice.attempt_id,
      p_answers: correctAnswers(practice),
    });
    assert.equal(result.status, 'completed');
    assert.equal(result.correct, result.total);
    assert.equal(result.heart_awarded, true);
    assert.equal(result.hearts.hearts, 1);
    assert.equal(result.xp_awarded, result.total * 2);
    assert.equal(Number(result.coins_awarded), 0);
  });

  test('a poor session gives XP for correct answers but no heart', async () => {
    const uid = await learner();
    await passLesson(db, uid, 'what-is-a-bank');
    await sql(db, `update public.user_stats set hearts = 2, hearts_updated_at = now() where user_id = $1`, [uid]);
    const practice = await rpc(db, uid, 'start_practice');
    await backdateSession(practice.attempt_id);
    const answers = correctAnswers(practice);
    const [first, second] = Object.keys(answers);
    answers[first] = 'wrong';
    answers[second] = 'wrong';
    const result = await rpc(db, uid, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: answers });
    assert.equal(result.heart_awarded, false);
    assert.equal(result.hearts.hearts, 2);
    assert.equal(result.xp_awarded, (result.total - 2) * 2);
  });

  test('counts for the streak and rejects replays and fast submissions', async () => {
    const uid = await learner();
    await passLesson(db, uid, 'what-is-a-bank');
    await sql(db, `update public.user_stats set streak_current = 3, streak_last_day = (now() at time zone 'UTC')::date - 1 where user_id = $1`, [uid]);

    const practice = await rpc(db, uid, 'start_practice');
    await assert.rejects(
      rpc(db, uid, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: correctAnswers(practice) }),
      /too_fast/,
    );
    await backdateSession(practice.attempt_id);
    const result = await rpc(db, uid, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: correctAnswers(practice) });
    assert.equal(result.streak.current, 4);
    await assert.rejects(
      rpc(db, uid, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: correctAnswers(practice) }),
      /attempt_closed/,
    );
  });

  test("users cannot complete someone else's session", async () => {
    const owner = await learner();
    const other = await learner();
    await passLesson(db, owner, 'what-is-a-bank');
    const practice = await rpc(db, owner, 'start_practice');
    await backdateSession(practice.attempt_id);
    await assert.rejects(
      rpc(db, other, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: {} }),
      /attempt_not_found/,
    );
  });
});
