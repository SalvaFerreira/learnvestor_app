// Runs the demo API (tools/db-tests/api.mjs) inside the browser: real migrations, seeds and
// RPCs on PGlite, with the data kept in IndexedDB so progress survives page reloads.
//
// Bundled by build.mjs into demo_api.js, which the demo's index.html loads before Flutter
// starts. In DEMO builds the app's DemoHttpClient (apps/mobile/lib/services/) sends every
// Supabase request to window.learnvestorDemoApi instead of the network.

import { PGlite } from '@electric-sql/pglite';
import { createApi, refreshDemoData, seedDemoLearners } from '../db-tests/api.mjs';
import { applySql } from '../db-tests/db.mjs';
import schema from './generated/schema.mjs';

const BASE = document.currentScript.src;
const DB_PREFIX = 'learnvestor-demo-';
// A new schema version gets a new database, so a redeployed demo never runs on old tables.
const DB_NAME = `${DB_PREFIX}${schema.version}`;

async function fetchBytes(file) {
  const res = await fetch(new URL(file, BASE));
  if (!res.ok) throw new Error(`${file}: HTTP ${res.status}`);
  return res.arrayBuffer();
}

async function openDb(assets, dataDir) {
  const db = await PGlite.create(dataDir, assets);
  const [{ ready }] = (await db.query("select to_regclass('auth.demo_ready') is not null as ready")).rows;
  if (ready) return db;
  const [{ partial }] = (await db.query("select to_regclass('auth.users') is not null as partial")).rows;
  if (partial) {
    // A previous first visit was interrupted halfway through the setup: start over.
    await db.close();
    await deleteDatabase(`/pglite/${DB_NAME}`);
    return openDb(assets, dataDir);
  }
  await applySql(db, schema.files);
  await seedDemoLearners(db);
  await db.exec('create table auth.demo_ready ()');
  return db;
}

function deleteDatabase(name) {
  return new Promise((resolve) => {
    const req = indexedDB.deleteDatabase(name);
    req.onsuccess = req.onerror = req.onblocked = () => resolve();
  });
}

async function removeOldDatabases() {
  const all = (await indexedDB.databases?.()) ?? [];
  for (const { name } of all) {
    if (name?.includes(DB_PREFIX) && !name.endsWith(DB_NAME)) await deleteDatabase(name);
  }
}

async function start() {
  const [wasm, data] = await Promise.all([fetchBytes('pglite.wasm'), fetchBytes('pglite.data')]);
  const assets = { wasmModule: await WebAssembly.compile(wasm), fsBundle: new Blob([data]) };
  let db;
  try {
    db = await openDb(assets, `idb://${DB_NAME}`);
  } catch (error) {
    // e.g. IndexedDB blocked (some private windows): still works, but nothing is kept.
    console.warn('LearnVestor demo: IndexedDB unavailable, progress will not be saved.', error);
    db = await openDb(assets, undefined);
  }
  await refreshDemoData(db);
  removeOldDatabases().catch(() => {});
  return { db, api: createApi(db) };
}

const demo = start();
demo.catch((error) => console.error('LearnVestor demo failed to start', error));

/**
 * (method, url, headersJson, body) → Promise<{ status, body }>.
 * Header names arrive in any case; the API expects lower case.
 */
window.learnvestorDemoApi = async (method, url, headersJson, body) => {
  try {
    const headers = Object.fromEntries(Object.entries(JSON.parse(headersJson)).map(([k, v]) => [k.toLowerCase(), v]));
    const { db, api } = await demo;
    const response = await api.handle({ method, url, headers, body: body ?? '' });
    // Writes made inside transactions (every RPC) are only flushed to IndexedDB on request:
    // flush before answering, so whatever the app shows as done survives a page reload.
    if (method !== 'GET') await db.syncToFs();
    return response;
  } catch (error) {
    console.error(error);
    return { status: 500, body: JSON.stringify({ message: String(error?.message ?? error) }) };
  }
};
