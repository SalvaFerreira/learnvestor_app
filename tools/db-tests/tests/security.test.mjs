// RLS policies and grants: what each API role can and cannot do.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';
import { as, createDb, createUser, onboard, rpc, sql } from '../harness.mjs';

let db, alice, bob;

before(async () => {
  db = await createDb();
  alice = await createUser(db);
  bob = await createUser(db);
  await onboard(db, alice, 'alice');
  await onboard(db, bob, 'bob');
});

describe('anonymous visitors', () => {
  test('cannot read any user data', async () => {
    for (const table of ['profiles', 'user_stats', 'portfolios', 'trades', 'waitlist_signups']) {
      await assert.rejects(as(db, null, (q) => q(`select * from public.${table}`)), /permission denied/, table);
    }
  });

  test('can join the waitlist, idempotently, without reading it', async () => {
    await rpc(db, null, 'join_waitlist', { p_email: '  Someone@Example.com ' });
    await rpc(db, null, 'join_waitlist', { p_email: 'someone@example.com' });
    const rows = await sql(db, `select email from public.waitlist_signups where email = 'someone@example.com'`);
    assert.equal(rows.length, 1);
    await assert.rejects(rpc(db, null, 'join_waitlist', { p_email: 'not-an-email' }), /invalid_email/);
  });

  test('cannot call game RPCs', async () => {
    await assert.rejects(rpc(db, null, 'get_my_state'), /permission denied/);
  });
});

describe('signed-in users', () => {
  test('only see their own rows', async () => {
    const profiles = await as(db, alice, (q) => q('select id from public.profiles'));
    assert.deepEqual(profiles.map((r) => r.id), [alice]);
    const stats = await as(db, alice, (q) => q('select user_id from public.user_stats'));
    assert.deepEqual(stats.map((r) => r.user_id), [alice]);
    const bobsPortfolio = await as(db, alice, (q) => q('select * from public.portfolios where user_id = $1', [bob]));
    assert.equal(bobsPortfolio.length, 0);
  });

  test('cannot write game state directly', async () => {
    await assert.rejects(as(db, alice, (q) => q('update public.user_stats set xp = 999999')), /permission denied/);
    await assert.rejects(as(db, alice, (q) => q('update public.portfolios set cash = 1000000')), /permission denied/);
    await assert.rejects(
      as(db, alice, (q) => q(`insert into public.xp_events (user_id, amount, reason, local_date) values ($1, 500, 'x', current_date)`, [alice])),
      /permission denied/,
    );
  });

  test('can edit only whitelisted profile columns of their own profile', async () => {
    await as(db, alice, (q) => q(`update public.profiles set locale = 'pt', display_name = 'Alice' where id = $1`, [alice]));
    const [row] = await sql(db, 'select locale, display_name from public.profiles where id = $1', [alice]);
    assert.deepEqual(row, { locale: 'pt', display_name: 'Alice' });

    await assert.rejects(as(db, alice, (q) => q(`update public.profiles set onboarded_at = null where id = $1`, [alice])), /permission denied/);
    const changed = await as(db, alice, (q) => q(`update public.profiles set locale = 'pt' where id = $1 returning id`, [bob]));
    assert.equal(changed.length, 0, 'RLS hides other profiles from UPDATE');
  });

  test('timezone must be valid and can change at most once per 24h', async () => {
    await assert.rejects(
      as(db, bob, (q) => q(`update public.profiles set timezone = 'Mars/Olympus' where id = $1`, [bob])),
      /invalid_timezone/,
    );
    await as(db, bob, (q) => q(`update public.profiles set timezone = 'America/New_York' where id = $1`, [bob]));
    await assert.rejects(
      as(db, bob, (q) => q(`update public.profiles set timezone = 'Asia/Tokyo' where id = $1`, [bob])),
      /timezone_change_too_soon/,
    );
  });

  test('cannot read answer keys', async () => {
    await assert.rejects(as(db, alice, (q) => q('select * from public.lesson_versions')), /permission denied/);
    await assert.rejects(as(db, alice, (q) => q('select * from public.lesson_translations')), /permission denied/);
  });

  test('can read reference data', async () => {
    const instruments = await as(db, alice, (q) => q('select symbol from public.instruments'));
    assert.ok(instruments.length > 10);
    const quotes = await as(db, alice, (q) => q('select symbol, price from public.quotes_latest'));
    assert.ok(quotes.length > 10);
  });
});

describe('onboarding', () => {
  test('rejects duplicate usernames (case-insensitive) and invalid ages', async () => {
    const carol = await createUser(db);
    await assert.rejects(onboard(db, carol, 'ALICE'), /username_taken/);
    await assert.rejects(
      rpc(db, carol, 'complete_onboarding', {
        p_username: 'carol', p_age_bracket: '13-15', p_daily_goal_xp: 30, p_country_code: 'PT', p_terms_version: 'v1',
      }),
      /invalid_age_bracket/,
    );
  });

  test('records consents', async () => {
    const rows = await sql(db, 'select kind, granted from public.consents where user_id = $1 order by kind', [alice]);
    assert.deepEqual(rows.map((r) => r.kind), ['analytics', 'marketing', 'privacy', 'terms']);
  });
});
