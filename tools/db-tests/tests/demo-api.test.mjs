// The demo API (api.mjs) used by dev-server.mjs and the web demo.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';
import { createApi, refreshDemoData } from '../api.mjs';
import { createDb, sql } from '../harness.mjs';

const BASE = 'http://demo.local';
let db;

before(async () => {
  db = await createDb();
});

async function call(api, method, path, { token, body } = {}) {
  const res = await api.handle({
    method,
    url: `${BASE}${path}`,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: body === undefined ? '' : JSON.stringify(body),
  });
  return { status: res.status, data: res.body ? JSON.parse(res.body) : undefined };
}

describe('demo API', () => {
  test('anonymous sign-in creates a profile and a working session', async () => {
    const api = createApi(db);
    const { status, data: session } = await call(api, 'POST', '/auth/v1/signup', { body: { data: { locale: 'pt' } } });
    assert.equal(status, 200);
    assert.equal(session.user.is_anonymous, true);

    const state = await call(api, 'POST', '/rest/v1/rpc/get_my_state', { token: session.access_token });
    assert.equal(state.status, 200);
    assert.equal(state.data.profile.locale, 'pt');
  });

  test('sessions survive a restart of the API (a page reload in the browser)', async () => {
    const { data: session } = await call(createApi(db), 'POST', '/auth/v1/signup', { body: {} });
    const restarted = createApi(db);

    const user = await call(restarted, 'GET', '/auth/v1/user', { token: session.access_token });
    assert.equal(user.data.id, session.user.id);

    const refreshed = await call(restarted, 'POST', '/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh_token } });
    assert.equal(refreshed.data.user.id, session.user.id);
    const reused = await call(restarted, 'POST', '/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh_token } });
    assert.equal(reused.status, 400, 'refresh tokens are single use');
  });

  test('rejects forged tokens and runs table reads under RLS', async () => {
    const api = createApi(db);
    const { data: session } = await call(api, 'POST', '/auth/v1/signup', { body: {} });
    const forged = `${session.access_token.slice(0, -4)}AAAA`;
    assert.equal((await call(api, 'GET', '/auth/v1/user', { token: forged })).status, 401);

    const profiles = await call(api, 'GET', '/rest/v1/profiles?select=id', { token: session.access_token });
    assert.deepEqual(profiles.data, [{ id: session.user.id }]);
    const anon = await call(api, 'GET', '/rest/v1/profiles?select=id');
    assert.equal(anon.status, 403);
  });

  test('delete-account removes the user', async () => {
    const api = createApi(db);
    const { data: session } = await call(api, 'POST', '/auth/v1/signup', { body: {} });
    assert.equal((await call(api, 'POST', '/functions/v1/delete-account', { token: session.access_token })).status, 200);
    assert.equal((await sql(db, 'select 1 from auth.users where id = $1', [session.user.id])).length, 0);
  });

  test('refreshDemoData keeps quotes tradable and saves today\'s portfolio point', async () => {
    await sql(db, `update public.quotes_latest set as_of = now() - interval '30 days'`);
    await refreshDemoData(db);

    const [{ stale }] = await sql(db, `select count(*)::int as stale from public.quotes_latest where as_of < now() - interval '1 hour'`);
    assert.equal(stale, 0);
    const [{ missing }] = await sql(db, `select count(*)::int as missing from public.portfolios p
      where not exists (select 1 from public.portfolio_snapshots s where s.portfolio_id = p.id and s.day = current_date)`);
    assert.equal(missing, 0);
  });
});
