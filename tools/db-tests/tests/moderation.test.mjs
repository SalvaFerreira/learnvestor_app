// Username moderation, content reports and the content quality views.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';
import { as, backdateAttempt, correctAnswers, createDb, createUser, onboard, passLesson, rpc, sql } from '../harness.mjs';

let db;
let n = 0;

async function learner(name = `mod${++n}`) {
  const uid = await createUser(db);
  await onboard(db, uid, name);
  return uid;
}

before(async () => {
  db = await createDb();
});

describe('usernames', () => {
  test('blocked terms are rejected, including leet spellings and underscores', async () => {
    for (const name of ['admin_pt', 'LearnVestorTeam', 'p_u_t_a', 'f0d4se', 'Merda123']) {
      const uid = await createUser(db);
      await assert.rejects(onboard(db, uid, name), /username_not_allowed/, name);
    }
  });

  test('ordinary names are accepted', async () => {
    for (const name of ['maria_silva', 'investidor99', 'Joao_P']) {
      await learner(name);
    }
  });

  test('three reports hide a name on the leaderboard (but not for its owner)', async () => {
    const target = await learner('sneaky_name');
    await passLesson(db, target, 'what-is-a-bank');
    const reporters = [await learner(), await learner(), await learner()];

    await rpc(db, reporters[0], 'report_username', { p_username: 'sneaky_name' });
    await rpc(db, reporters[0], 'report_username', { p_username: 'SNEAKY_NAME' }); // same reporter twice
    let board = await rpc(db, reporters[0], 'get_weekly_leaderboard');
    assert.ok(board.entries.some((e) => e.username === 'sneaky_name'));

    await rpc(db, reporters[1], 'report_username', { p_username: 'sneaky_name' });
    await rpc(db, reporters[2], 'report_username', { p_username: 'sneaky_name' });
    board = await rpc(db, reporters[0], 'get_weekly_leaderboard');
    assert.ok(!board.entries.some((e) => e.username === 'sneaky_name'));
    assert.ok(board.entries.some((e) => e.username.startsWith('learner_')));

    const own = await rpc(db, target, 'get_weekly_leaderboard');
    assert.ok(own.entries.some((e) => e.is_me && e.username === 'sneaky_name'));
  });

  test('users cannot read reports', async () => {
    const uid = await learner();
    await assert.rejects(as(db, uid, (q) => q('select * from public.username_reports')), /permission denied/);
  });
});

describe('content reports and quality', () => {
  test('learners can report an exercise and see only their own reports', async () => {
    const a = await learner();
    const b = await learner();
    await rpc(db, a, 'report_content', {
      p_lesson_id: 'what-is-a-bank', p_exercise_id: 'deposit-guarantee', p_reason: 'unclear', p_message: 'Não percebi',
    });
    await assert.rejects(
      rpc(db, a, 'report_content', { p_lesson_id: 'what-is-a-bank', p_exercise_id: 'x', p_reason: 'spam' }),
      /invalid_reason/,
    );
    assert.equal((await as(db, a, (q) => q('select * from public.content_reports'))).length, 1);
    assert.equal((await as(db, b, (q) => q('select * from public.content_reports'))).length, 0);

    const [open] = await sql(db, `select * from private.open_content_reports where exercise_id = 'deposit-guarantee'`);
    assert.equal(Number(open.reports), 1);
    assert.deepEqual(open.messages, ['Não percebi']);
  });

  test('quality views compute first-try error rate and completion', async () => {
    const uid = await learner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'risk-vs-reward' });
    await backdateAttempt(db, lesson.attempt_id);
    const answers = correctAnswers(lesson);
    answers['no-guarantee'] = true; // wrong
    await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: answers });

    const [wrong] = await sql(db, `select * from private.exercise_quality where lesson_id = 'risk-vs-reward' and exercise_id = 'no-guarantee'`);
    assert.equal(Number(wrong.error_rate), 1);
    const [right] = await sql(db, `select * from private.exercise_quality where lesson_id = 'risk-vs-reward' and exercise_id = 'volatility'`);
    assert.equal(Number(right.error_rate), 0);
    const [funnel] = await sql(db, `select * from private.lesson_funnel where lesson_id = 'risk-vs-reward'`);
    assert.equal(Number(funnel.completed), 1);
  });

  test('the views are not reachable through the API', async () => {
    const uid = await learner();
    await assert.rejects(as(db, uid, (q) => q('select * from private.exercise_quality')), /permission denied/);
  });
});
