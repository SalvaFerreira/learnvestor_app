// Lessons, XP, hearts, streaks and achievements.
import assert from 'node:assert/strict';
import { before, beforeEach, describe, test } from 'node:test';
import { backdateAttempt, correctAnswers, createDb, createUser, onboard, passLesson, rpc, sql } from '../harness.mjs';

let db;
let n = 0;

async function newLearner(meta) {
  const uid = await createUser(db, meta);
  await onboard(db, uid, `learner${++n}`);
  return uid;
}

const state = (uid) => rpc(db, uid, 'get_my_state');

before(async () => {
  db = await createDb();
});

describe('signup', () => {
  test('creates profile, full hearts and a welcome portfolio', async () => {
    const uid = await createUser(db, { locale: 'pt', timezone: 'Europe/Lisbon' });
    const s = await state(uid);
    assert.equal(s.profile.locale, 'pt');
    assert.equal(s.profile.timezone, 'Europe/Lisbon');
    assert.equal(s.stats.hearts, 6);
    assert.equal(Number(s.portfolio.cash), 100);
    assert.equal(s.profile.onboarded, false);
  });

  test('falls back to safe defaults for invalid metadata', async () => {
    const uid = await createUser(db, { locale: 'xx', timezone: 'Nowhere/Land' });
    const s = await state(uid);
    assert.equal(s.profile.locale, 'en');
    assert.equal(s.profile.timezone, 'UTC');
  });
});

describe('learning path', () => {
  test('first lesson of each free track is unlocked, the rest locked, premium gated', async () => {
    const uid = await newLearner();
    const path = await rpc(db, uid, 'get_learning_path', { p_locale: 'pt' });
    const statuses = Object.fromEntries(path.map((t) => [t.id, t.units.flatMap((u) => u.lessons.map((l) => l.status))]));
    for (const track of ['banks', 'taxes', 'investment', 'mindset']) {
      const [first, ...rest] = statuses[track];
      assert.equal(first, 'unlocked', track);
      assert.ok(rest.every((s) => s === 'locked'), track);
    }
    assert.ok(statuses.advanced.every((s) => s === 'premium'));
    assert.equal(path[0].title, 'Dinheiro no Dia a Dia');
    assert.deepEqual(path[0].units[0].lessons.slice(0, 3).map((l) => l.id), ['what-is-a-bank', 'emergency-fund', 'compound-interest']);
  });

  test('Portugal-only lessons are hidden for learners elsewhere', async () => {
    const uid = await createUser(db);
    await rpc(db, uid, 'complete_onboarding', {
      p_username: `abroad${++n}`, p_age_bracket: '25-34', p_daily_goal_xp: 20, p_country_code: 'ES', p_terms_version: 'v1',
    });
    const path = await rpc(db, uid, 'get_learning_path');
    assert.ok(!path.some((t) => t.id === 'taxes'), 'the whole taxes track is PT-only');
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'gross-vs-net' }), /lesson_not_found/);
  });

  test('locked and premium lessons cannot be started', async () => {
    const uid = await newLearner();
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'emergency-fund' }), /lesson_locked/);
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'fees-matter' }), /premium_required/);
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'does-not-exist' }), /lesson_not_found/);
  });

  test('start_lesson returns localized exercises with answers for instant feedback', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank', p_locale: 'pt' });
    assert.equal(lesson.title, 'Como Funcionam os Bancos');
    assert.equal(lesson.exercises.length, 5);
    assert.equal(lesson.exercises[0].type, 'info');
    assert.ok(!('answer' in lesson.exercises[0]));
    assert.deepEqual(lesson.exercises[4].answer, [0, 1, 2, 3]);
  });
});

describe('completing lessons', () => {
  test('rejects impossibly fast completions', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    await assert.rejects(
      rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: correctAnswers(lesson) }),
      /too_fast/,
    );
  });

  test('a perfect first completion awards XP + bonus, coins, streak, achievement and unlocks the next lesson', async () => {
    const uid = await newLearner();
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.status, 'completed');
    assert.equal(result.stars, 3);
    assert.equal(result.xp_awarded, 25); // 20 + 5 perfect bonus
    assert.equal(Number(result.coins_awarded), 30);
    assert.equal(result.streak.current, 1);
    assert.deepEqual(result.new_achievements, ['first_lesson']);

    const s = await state(uid);
    assert.equal(s.stats.xp, 25);
    assert.equal(s.stats.gems, 10); // first_lesson reward
    assert.equal(Number(s.portfolio.cash), 130);
    assert.equal(s.stats.streak_extended_today, true);

    const path = await rpc(db, uid, 'get_learning_path');
    assert.deepEqual(path[0].units[0].lessons.slice(0, 3).map((l) => l.status), ['completed', 'unlocked', 'locked']);
  });

  test('replays give reduced XP and no virtual money', async () => {
    const uid = await newLearner();
    await passLesson(db, uid, 'what-is-a-bank');
    const replay = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(replay.first_completion, false);
    assert.equal(replay.xp_awarded, 6); // 20 / 3
    assert.equal(Number(replay.coins_awarded), 0);
    const s = await state(uid);
    assert.equal(Number(s.portfolio.cash), 130);
    assert.equal(s.stats.lessons_completed, 1);
  });

  test('a completed attempt cannot be submitted twice', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    await backdateAttempt(db, lesson.attempt_id);
    await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: correctAnswers(lesson) });
    await assert.rejects(
      rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: correctAnswers(lesson) }),
      /attempt_closed/,
    );
  });

  test("users cannot complete someone else's attempt", async () => {
    const owner = await newLearner();
    const thief = await newLearner();
    const lesson = await rpc(db, owner, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    await backdateAttempt(db, lesson.attempt_id);
    await assert.rejects(
      rpc(db, thief, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: correctAnswers(lesson) }),
      /attempt_not_found/,
    );
  });

  test('levels up when crossing the XP threshold', async () => {
    const uid = await newLearner();
    await sql(db, 'update public.user_stats set xp = 90 where user_id = $1', [uid]);
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.level, 2);
    assert.equal(result.leveled_up, true);
  });

  test('daily XP cap limits farming', async () => {
    const uid = await newLearner();
    await sql(
      db,
      `insert into public.xp_events (user_id, amount, reason, local_date) values ($1, 1495, 'test', (now() at time zone 'UTC')::date)`,
      [uid],
    );
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.xp_awarded, 5);
  });
});

describe('hearts', () => {
  test('mistakes cost hearts and lower the stars, even if lose_heart was never called', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    await backdateAttempt(db, lesson.attempt_id);
    const answers = correctAnswers(lesson);
    answers['how-banks-earn'] = 2; // wrong
    const result = await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: answers });
    assert.equal(result.correct, 3);
    assert.equal(result.stars, 2);
    assert.equal(result.xp_awarded, 20); // no perfect bonus
    assert.equal(result.hearts.hearts, 5);
  });

  test('lose_heart takes hearts immediately and is not charged twice at completion', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    const h = await rpc(db, uid, 'lose_heart', { p_attempt_id: lesson.attempt_id });
    assert.equal(h.hearts, 5);
    assert.ok(h.next_heart_at, 'regeneration timer started');
    await backdateAttempt(db, lesson.attempt_id);
    const answers = correctAnswers(lesson);
    answers['deposit-guarantee'] = false;
    const result = await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: answers });
    assert.equal(result.hearts.hearts, 5);
  });

  test('cannot start a lesson with zero hearts; hearts regenerate over time', async () => {
    const uid = await newLearner();
    await sql(db, `update public.user_stats set hearts = 0, hearts_updated_at = now() where user_id = $1`, [uid]);
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' }), /out_of_hearts/);

    await sql(db, `update public.user_stats set hearts_updated_at = now() - interval '150 minutes' where user_id = $1`, [uid]);
    const s = await state(uid);
    assert.equal(s.stats.hearts, 2); // 1 per hour
    await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
  });

  test('more mistakes than hearts fails the lesson without rewards', async () => {
    const uid = await newLearner();
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank' });
    await sql(db, `update public.user_stats set hearts = 1, hearts_updated_at = now() where user_id = $1`, [uid]);
    await backdateAttempt(db, lesson.attempt_id);
    const result = await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: {} });
    assert.equal(result.status, 'failed');
    assert.equal(result.reason, 'out_of_hearts');
    const s = await state(uid);
    assert.equal(s.stats.xp, 0);
    assert.equal(s.stats.hearts, 0);
  });

  test('gems refill hearts', async () => {
    const uid = await newLearner();
    await sql(db, `update public.user_stats set hearts = 1, gems = 60, hearts_updated_at = now() where user_id = $1`, [uid]);
    const h = await rpc(db, uid, 'refill_hearts');
    assert.equal(h.hearts, 6);
    assert.equal(h.gems, 10);
    await assert.rejects(rpc(db, uid, 'refill_hearts'), /hearts_full/);
  });
});

describe('streaks', () => {
  let uid;
  const setStreak = (current, daysAgo, freezes = 0) =>
    sql(
      db,
      `update public.user_stats set streak_current = $2, streak_longest = greatest(streak_longest, $2),
         streak_last_day = (now() at time zone 'UTC')::date - $3::int, streak_freezes = $4 where user_id = $1`,
      [uid, current, daysAgo, freezes],
    );

  beforeEach(async () => {
    uid = await newLearner();
  });

  test('practising the day after extends the streak', async () => {
    await setStreak(4, 1);
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.streak.current, 5);
  });

  test('a missed day without freezes resets the streak', async () => {
    await setStreak(4, 2);
    assert.equal((await state(uid)).stats.streak, 0);
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.streak.current, 1);
  });

  test('a streak freeze covers a missed day', async () => {
    await setStreak(4, 2, 1);
    assert.equal((await state(uid)).stats.streak, 4);
    const result = await passLesson(db, uid, 'what-is-a-bank');
    assert.equal(result.streak.current, 5);
    assert.equal(result.streak.freezes_used, 1);
  });

  test('a second lesson on the same day does not extend it again', async () => {
    await passLesson(db, uid, 'what-is-a-bank');
    const second = await passLesson(db, uid, 'emergency-fund');
    assert.equal(second.streak.current, 1);
    assert.equal(second.streak.extended_today, false);
  });
});

describe('plus subscribers', () => {
  test('get premium lessons and unlimited hearts', async () => {
    const uid = await newLearner();
    // Applied as the webhook would (service role); users cannot call this (see security tests).
    await sql(db, `select public.svc_apply_entitlement($1, 'plus', 'app_store', 'plus_monthly', true, now() + interval '30 days', 'tx1')`, [uid]);

    const s = await state(uid);
    assert.equal(s.is_plus, true);
    const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'etfs-and-index-funds' });
    const h = await rpc(db, uid, 'lose_heart', { p_attempt_id: lesson.attempt_id });
    assert.equal(h.hearts, 6);
    assert.equal(h.unlimited, true);
  });

  test('expired subscriptions lose access', async () => {
    const uid = await newLearner();
    await sql(db, `select public.svc_apply_entitlement($1, 'plus', 'play_store', 'plus_yearly', true, now() - interval '1 day', 'tx2')`, [uid]);
    assert.equal((await state(uid)).is_plus, false);
    await assert.rejects(rpc(db, uid, 'start_lesson', { p_lesson_id: 'etfs-and-index-funds' }), /premium_required/);
  });

  test('gem purchases are credited once per transaction', async () => {
    const uid = await newLearner();
    const first = await sql(db, `select public.svc_credit_gems($1, 500, 'app_store', 'txn-abc', 'gems_500') as ok`, [uid]);
    const retry = await sql(db, `select public.svc_credit_gems($1, 500, 'app_store', 'txn-abc', 'gems_500') as ok`, [uid]);
    assert.equal(first[0].ok, true);
    assert.equal(retry[0].ok, false);
    assert.equal((await state(uid)).stats.gems, 500);
  });
});

describe('social and GDPR', () => {
  test('weekly leaderboard ranks by XP earned this week', async () => {
    const a = await newLearner();
    const b = await newLearner();
    await passLesson(db, a, 'what-is-a-bank');
    await passLesson(db, b, 'risk-vs-reward');
    const board = await rpc(db, a, 'get_weekly_leaderboard');
    const me = board.entries.find((e) => e.is_me);
    assert.ok(me, 'caller appears in the ranking');
    assert.equal(Number(me.xp), 25);
    assert.equal(board.me.rank, me.rank);
    // risk-vs-reward gives more XP (35 + 5) than what-is-a-bank (20 + 5)
    const xps = board.entries.map((e) => Number(e.xp));
    assert.deepEqual(xps, [...xps].sort((x, y) => y - x));
    assert.ok(b);
  });

  test('achievements list shows progress', async () => {
    const uid = await newLearner();
    await passLesson(db, uid, 'what-is-a-bank');
    const list = await rpc(db, uid, 'get_my_achievements', { p_locale: 'pt' });
    const first = list.find((a) => a.id === 'first_lesson');
    assert.equal(first.title, 'Primeiros Passos');
    assert.ok(first.unlocked_at);
    const five = list.find((a) => a.id === 'lessons_5');
    assert.equal(five.progress, 1);
    assert.equal(five.unlocked_at, null);
  });

  test('export contains the user data and nothing from other users', async () => {
    const uid = await newLearner();
    await passLesson(db, uid, 'what-is-a-bank');
    const data = await rpc(db, uid, 'export_my_data');
    assert.equal(data.profile.id, uid);
    assert.equal(data.lesson_progress.length, 1);
    assert.ok(data.xp_events.every((e) => e.user_id === uid));
  });

  test('deleting the auth user removes all their data', async () => {
    const uid = await newLearner();
    await passLesson(db, uid, 'what-is-a-bank');
    await sql(db, 'delete from auth.users where id = $1', [uid]);
    for (const table of ['profiles', 'user_stats', 'portfolios', 'lesson_attempts', 'xp_events', 'currency_ledger', 'consents']) {
      const column = table === 'profiles' ? 'id' : 'user_id';
      const rows = await sql(db, `select 1 from public.${table} where ${column} = $1`, [uid]);
      assert.equal(rows.length, 0, table);
    }
  });
});
