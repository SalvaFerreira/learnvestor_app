// LOCAL DEMO ONLY: a tiny stand-in for the Supabase API so the app can be tried without
// Docker or a Supabase account. It runs the real migrations, seeds and RPCs on PGlite
// (in memory: data is lost when it stops) and implements just what the app calls:
//   Auth  : email code sign-in (the code is always 123456), refresh, user, logout
//   REST  : RPCs, simple selects (eq filters + order) and profile PATCH, all under RLS
//   Funcs : delete-account
// Realtime is not implemented (the app falls back to the REST snapshot of quotes).
//
//   npm run dev   →   http://127.0.0.1:54321

import { createHmac, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { as, createDb, onboard, sql } from './harness.mjs';

const PORT = Number(process.env.PORT ?? 54321);
const DEMO_CODE = '123456';
const SECRET = randomBytes(32);
const IDENT = /^[a-z_][a-z0-9_]*$/;

const db = await createDb();
await seedDemoLearners();

const pendingSignups = new Map(); // email -> user metadata sent with the code request
const refreshTokens = new Map(); // token -> user id

// ---- JWT -----------------------------------------------------------------------------------

const b64 = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

function signJwt(payload) {
  const head = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(payload)}`;
  return `${head}.${createHmac('sha256', SECRET).update(head).digest('base64url')}`;
}

function verifyJwt(token) {
  const [h, p, s] = (token ?? '').split('.');
  if (!s || createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url') !== s) return null;
  const payload = JSON.parse(Buffer.from(p, 'base64url').toString());
  return payload.exp > Date.now() / 1000 ? payload : null;
}

async function sessionFor(userId) {
  const [user] = await sql(db, 'select id, email, raw_user_meta_data, created_at from auth.users where id = $1', [userId]);
  const now = Math.floor(Date.now() / 1000);
  const refresh = randomBytes(24).toString('hex');
  refreshTokens.set(refresh, userId);
  return {
    access_token: signJwt({ sub: userId, email: user.email, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + 3600 }),
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: now + 3600,
    refresh_token: refresh,
    user: userJson(user),
  };
}

const userJson = (u) => ({
  id: u.id,
  aud: 'authenticated',
  role: 'authenticated',
  email: u.email,
  app_metadata: { provider: 'email' },
  user_metadata: u.raw_user_meta_data ?? {},
  created_at: new Date(u.created_at).toISOString(),
  email_confirmed_at: new Date(u.created_at).toISOString(),
});

// ---- HTTP plumbing ------------------------------------------------------------------------

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, prefer, accept-profile, content-profile, x-supabase-api-version, range',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'content-range',
};

function send(res, status, body) {
  res.writeHead(status, { ...CORS, 'Content-Type': 'application/json' });
  res.end(body === undefined ? '' : JSON.stringify(body));
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const text = Buffer.concat(chunks).toString();
  return text ? JSON.parse(text) : {};
}

function pgError(res, error) {
  const message = error.message ?? String(error);
  const status = /permission denied/.test(message) ? 403 : error.code === '28000' ? 401 : 400;
  send(res, status, { code: error.code ?? 'P0001', message, details: null, hint: null });
}

const userFrom = (req) => verifyJwt(req.headers.authorization?.replace(/^Bearer\s+/i, ''))?.sub ?? null;

// ---- routes -------------------------------------------------------------------------------

async function handleAuth(req, res, path, url) {
  if (path === '/auth/v1/otp' && req.method === 'POST') {
    const { email, data } = await readBody(req);
    pendingSignups.set(email.toLowerCase(), data ?? {});
    console.log(`[auth] code for ${email}: ${DEMO_CODE}`);
    return send(res, 200, {});
  }
  if (path === '/auth/v1/verify' && req.method === 'POST') {
    const { email, token } = await readBody(req);
    const normalized = (email ?? '').toLowerCase();
    if (token !== DEMO_CODE || !pendingSignups.has(normalized)) {
      return send(res, 403, { code: 403, error_code: 'otp_expired', msg: 'Token has expired or is invalid' });
    }
    let [user] = await sql(db, 'select id from auth.users where email = $1', [normalized]);
    if (!user) {
      [user] = await sql(db, 'insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id', [
        normalized,
        JSON.stringify(pendingSignups.get(normalized)),
      ]);
    }
    return send(res, 200, await sessionFor(user.id));
  }
  if (path === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token') {
    const { refresh_token } = await readBody(req);
    const userId = refreshTokens.get(refresh_token);
    refreshTokens.delete(refresh_token);
    if (!userId) return send(res, 400, { code: 400, error_code: 'refresh_token_not_found', msg: 'Invalid Refresh Token' });
    return send(res, 200, await sessionFor(userId));
  }
  if (path === '/auth/v1/user') {
    const uid = userFrom(req);
    if (!uid) return send(res, 401, { code: 401, msg: 'invalid JWT' });
    const [user] = await sql(db, 'select id, email, raw_user_meta_data, created_at from auth.users where id = $1', [uid]);
    return user ? send(res, 200, userJson(user)) : send(res, 404, { msg: 'User not found' });
  }
  if (path === '/auth/v1/logout') return send(res, 204);
  return send(res, 404, { msg: `auth route not implemented: ${path}` });
}

async function handleRpc(req, res, fn) {
  if (!IDENT.test(fn)) return send(res, 404, { message: 'unknown function' });
  const args = (await readBody(req)) ?? {}; // RPCs without parameters send `null`
  const names = Object.keys(args).filter((n) => IDENT.test(n));
  const call = `select public.${fn}(${names.map((n, i) => `${n} => $${i + 1}`).join(', ')}) as result`;
  try {
    const rows = await as(db, userFrom(req), (q) => q(call, names.map((n) => args[n])));
    send(res, 200, rows[0]?.result ?? null);
  } catch (error) {
    pgError(res, error);
  }
}

/** PostgREST subset: ?select=a,b&col=eq.value&order=col.desc */
function parseQuery(url) {
  const columns = (url.searchParams.get('select') ?? '*').split(',').map((c) => c.trim());
  if (!columns.every((c) => c === '*' || IDENT.test(c))) throw new Error('unsupported select');
  const where = [];
  const params = [];
  let order = '';
  for (const [key, value] of url.searchParams) {
    if (key === 'select') continue;
    if (key === 'order') {
      const [col, dir] = value.split('.');
      if (!IDENT.test(col)) throw new Error('unsupported order');
      order = ` order by ${col} ${dir === 'desc' ? 'desc' : 'asc'}`;
      continue;
    }
    const m = value.match(/^eq\.(.*)$/);
    if (!IDENT.test(key) || !m) throw new Error(`unsupported filter ${key}`);
    params.push(m[1]);
    where.push(`${key}::text = $${params.length}`);
  }
  return { columns: columns.join(', '), where: where.length ? ` where ${where.join(' and ')}` : '', order, params };
}

async function handleTable(req, res, table, url) {
  if (!IDENT.test(table)) return send(res, 404, { message: 'unknown table' });
  const uid = userFrom(req);
  try {
    const { columns, where, order, params } = parseQuery(url);
    if (req.method === 'GET') {
      const rows = await as(db, uid, (q) =>
        q(`select coalesce(json_agg(t), '[]'::json) as data from (select ${columns} from public.${table}${where}${order}) t`, params),
      );
      return send(res, 200, rows[0].data);
    }
    if (req.method === 'PATCH') {
      const body = await readBody(req);
      const keys = Object.keys(body).filter((k) => IDENT.test(k));
      const sets = keys.map((k, i) => `${k} = $${params.length + i + 1}`).join(', ');
      await as(db, uid, (q) => q(`update public.${table} set ${sets}${where}`, [...params, ...keys.map((k) => body[k])]));
      return send(res, 204);
    }
    return send(res, 405, { message: 'method not supported by the dev server' });
  } catch (error) {
    pgError(res, error);
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;
  try {
    if (req.method === 'OPTIONS') return send(res, 204);
    if (path.startsWith('/auth/v1/')) return await handleAuth(req, res, path, url);
    if (path.startsWith('/rest/v1/rpc/')) return await handleRpc(req, res, path.slice('/rest/v1/rpc/'.length));
    if (path.startsWith('/rest/v1/')) return await handleTable(req, res, path.slice('/rest/v1/'.length), url);
    if (path === '/functions/v1/delete-account' && req.method === 'POST') {
      const uid = userFrom(req);
      if (!uid) return send(res, 401, { error: 'unauthorized' });
      await sql(db, 'delete from auth.users where id = $1', [uid]);
      return send(res, 200, { status: 'deleted' });
    }
    send(res, 404, { message: `not implemented by the dev server: ${req.method} ${path}` });
  } catch (error) {
    console.error(error);
    send(res, 500, { message: error.message });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`LearnVestor dev API on http://127.0.0.1:${PORT}  (sign-in code: ${DEMO_CODE})`);
});

/** A few other learners so the weekly leaderboard is not empty. */
async function seedDemoLearners() {
  const learners = [['ana_invests', 180], ['joao_etf', 120], ['marta_bolsa', 95], ['rui_poupa', 40]];
  for (const [username, xp] of learners) {
    const [{ id }] = await sql(db, 'insert into auth.users (email) values ($1) returning id', [`${username}@demo.local`]);
    await onboard(db, id, username);
    await sql(db, `insert into public.xp_events (user_id, amount, reason, local_date) values ($1, $2, 'demo', current_date)`, [id, xp]);
    await sql(db, 'update public.user_stats set xp = $2, level = private.level_for_xp($2) where user_id = $1', [id, xp]);
  }
}

