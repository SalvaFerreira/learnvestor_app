// LOCAL DEMO ONLY: the part of the Supabase API that the app calls, implemented on PGlite
// with the real migrations, seeds and RPCs (everything runs under RLS, as on Supabase):
//   Auth  : anonymous sign-in (there are no logins), refresh, user, logout
//   REST  : RPCs, simple selects (eq filters + order) and profile PATCH
//   Funcs : delete-account
// Realtime is not implemented (the app falls back to the REST snapshot of quotes).
//
// No Node APIs here: dev-server.mjs serves it over HTTP and the web demo
// (tools/web-demo) calls it inside the browser.

import { as, onboard, sql } from './db.mjs';

const IDENT = /^[a-z_][a-z0-9_]*$/;
const TOKEN_TTL = 3600;

const DEMO_LEARNERS = [['ana_invests', 180], ['joao_etf', 120], ['marta_bolsa', 95], ['rui_poupa', 40]];

/** A few other learners so the weekly leaderboard is not empty. */
export async function seedDemoLearners(db) {
  for (const [username, xp] of DEMO_LEARNERS) {
    const [{ id }] = await sql(db, 'insert into auth.users (is_anonymous) values (true) returning id');
    await onboard(db, id, username);
    await sql(db, `insert into public.xp_events (user_id, amount, reason, local_date) values ($1, $2, 'demo', current_date)`, [id, xp]);
    await sql(db, 'update public.user_stats set xp = $2, level = private.level_for_xp($2) where user_id = $1', [id, xp]);
  }
}

/**
 * For a database that is kept between sessions (the web demo): the sample quotes and the
 * demo learners' XP are moved to "now", so trades never hit stale prices and the weekly
 * leaderboard is never empty.
 */
export async function refreshDemoData(db) {
  await sql(db, 'update public.quotes_latest set as_of = now()');
  await sql(db, 'update public.fx_rates set as_of = current_date');
  await sql(db, `update public.xp_events set created_at = now(), local_date = current_date where reason = 'demo'`);
}

// ---- JWT (HS256 with WebCrypto, available in browsers and Node) -----------------------------

const encoder = new TextEncoder();

const b64url = (bytes) =>
  btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join('')).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
const fromB64url = (text) => Uint8Array.from(atob(text.replaceAll('-', '+').replaceAll('_', '/')), (c) => c.charCodeAt(0));
const randomHex = (bytes) => Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) => b.toString(16).padStart(2, '0')).join('');

export function createApi(db) {
  let keyPromise;
  const key = () =>
    (keyPromise ??= sql(db, 'select secret from auth.demo_secret').then(([row]) =>
      crypto.subtle.importKey('raw', encoder.encode(row.secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']),
    ));

  async function signature(head) {
    return b64url(new Uint8Array(await crypto.subtle.sign('HMAC', await key(), encoder.encode(head))));
  }

  async function signJwt(payload) {
    const head = `${b64url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })))}.${b64url(encoder.encode(JSON.stringify(payload)))}`;
    return `${head}.${await signature(head)}`;
  }

  /** User id from a valid, unexpired access token; null otherwise. */
  async function userFrom(headers) {
    const token = (headers.authorization ?? '').replace(/^Bearer\s+/i, '');
    const [h, p, s] = token.split('.');
    if (!s || (await signature(`${h}.${p}`)) !== s) return null;
    const payload = JSON.parse(new TextDecoder().decode(fromB64url(p)));
    return payload.exp > Date.now() / 1000 ? payload.sub : null;
  }

  const userJson = (u) => ({
    id: u.id,
    aud: 'authenticated',
    role: 'authenticated',
    email: '',
    phone: '',
    is_anonymous: true,
    app_metadata: {},
    user_metadata: u.raw_user_meta_data ?? {},
    identities: [],
    created_at: new Date(u.created_at).toISOString(),
  });

  async function sessionFor(userId) {
    const [user] = await sql(db, 'select id, raw_user_meta_data, created_at from auth.users where id = $1', [userId]);
    const now = Math.floor(Date.now() / 1000);
    const refresh = randomHex(24);
    await sql(db, 'insert into auth.refresh_tokens (token, user_id) values ($1, $2)', [refresh, userId]);
    return {
      access_token: await signJwt({ sub: userId, role: 'authenticated', aud: 'authenticated', is_anonymous: true, iat: now, exp: now + TOKEN_TTL }),
      token_type: 'bearer',
      expires_in: TOKEN_TTL,
      expires_at: now + TOKEN_TTL,
      refresh_token: refresh,
      user: userJson(user),
    };
  }

  const json = (status, body) => ({ status, body: body === undefined ? '' : JSON.stringify(body) });

  function pgError(error) {
    const message = error.message ?? String(error);
    const status = /permission denied/.test(message) ? 403 : error.code === '28000' ? 401 : 400;
    return json(status, { code: error.code ?? 'P0001', message, details: null, hint: null });
  }

  async function handleAuth(method, path, url, headers, body) {
    // signInAnonymously(): a signup without email or password.
    if (path === '/auth/v1/signup' && method === 'POST') {
      const [user] = await sql(db, 'insert into auth.users (is_anonymous, raw_user_meta_data) values (true, $1) returning id', [
        JSON.stringify(body.data ?? {}),
      ]);
      return json(200, await sessionFor(user.id));
    }
    if (path === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token') {
      const [row] = await sql(db, 'delete from auth.refresh_tokens where token = $1 returning user_id', [body.refresh_token ?? '']);
      if (!row) return json(400, { code: 400, error_code: 'refresh_token_not_found', msg: 'Invalid Refresh Token' });
      return json(200, await sessionFor(row.user_id));
    }
    if (path === '/auth/v1/user') {
      const uid = await userFrom(headers);
      if (!uid) return json(401, { code: 401, msg: 'invalid JWT' });
      const [user] = await sql(db, 'select id, raw_user_meta_data, created_at from auth.users where id = $1', [uid]);
      return user ? json(200, userJson(user)) : json(404, { msg: 'User not found' });
    }
    if (path === '/auth/v1/logout') return json(204);
    return json(404, { msg: `auth route not implemented: ${path}` });
  }

  async function handleRpc(fn, uid, args) {
    if (!IDENT.test(fn)) return json(404, { message: 'unknown function' });
    const names = Object.keys(args ?? {}).filter((n) => IDENT.test(n)); // RPCs without parameters send `null`
    const call = `select public.${fn}(${names.map((n, i) => `${n} => $${i + 1}`).join(', ')}) as result`;
    try {
      const rows = await as(db, uid, (q) => q(call, names.map((n) => args[n])));
      return json(200, rows[0]?.result ?? null);
    } catch (error) {
      return pgError(error);
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

  async function handleTable(method, table, url, uid, body) {
    if (!IDENT.test(table)) return json(404, { message: 'unknown table' });
    try {
      const { columns, where, order, params } = parseQuery(url);
      if (method === 'GET') {
        const rows = await as(db, uid, (q) =>
          q(`select coalesce(json_agg(t), '[]'::json) as data from (select ${columns} from public.${table}${where}${order}) t`, params),
        );
        return json(200, rows[0].data);
      }
      if (method === 'PATCH') {
        const keys = Object.keys(body).filter((k) => IDENT.test(k));
        const sets = keys.map((k, i) => `${k} = $${params.length + i + 1}`).join(', ');
        await as(db, uid, (q) => q(`update public.${table} set ${sets}${where}`, [...params, ...keys.map((k) => body[k])]));
        return json(204);
      }
      return json(405, { message: 'method not supported by the demo API' });
    } catch (error) {
      return pgError(error);
    }
  }

  /**
   * One HTTP-like request → { status, body } (body is JSON text, or '' when empty).
   * [headers] keys must be lower case.
   */
  async function handle({ method, url, headers = {}, body = '' }) {
    const parsed = new URL(url);
    const path = parsed.pathname;
    const data = body ? JSON.parse(body) : {};
    if (path.startsWith('/auth/v1/')) return handleAuth(method, path, parsed, headers, data ?? {});
    const uid = await userFrom(headers);
    if (path.startsWith('/rest/v1/rpc/')) return handleRpc(path.slice('/rest/v1/rpc/'.length), uid, data);
    if (path.startsWith('/rest/v1/')) return handleTable(method, path.slice('/rest/v1/'.length), parsed, uid, data ?? {});
    if (path === '/functions/v1/delete-account' && method === 'POST') {
      if (!uid) return json(401, { error: 'unauthorized' });
      await sql(db, 'delete from auth.users where id = $1', [uid]);
      return json(200, { status: 'deleted' });
    }
    return json(404, { message: `not implemented by the demo API: ${method} ${path}` });
  }

  return { handle };
}
