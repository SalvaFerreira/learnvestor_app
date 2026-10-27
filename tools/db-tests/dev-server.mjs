// LOCAL DEMO ONLY: serves the demo API (api.mjs) over HTTP so `flutter run` can be tried
// without Docker or a Supabase account. The database is in memory: data is lost when it stops.
// The published web demo runs the same API inside the browser instead (tools/web-demo).
//
//   npm run dev   →   http://127.0.0.1:54321

import { createServer } from 'node:http';
import { createApi, seedDemoLearners } from './api.mjs';
import { createDb } from './harness.mjs';

const PORT = Number(process.env.PORT ?? 54321);

const db = await createDb();
await seedDemoLearners(db);
const api = createApi(db);

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, prefer, accept-profile, content-profile, x-supabase-api-version, range',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'content-range',
};

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks).toString();
}

const server = createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, CORS);
      return res.end();
    }
    const { status, body } = await api.handle({
      method: req.method,
      url: `http://${req.headers.host}${req.url}`,
      headers: req.headers,
      body: await readBody(req),
    });
    res.writeHead(status, { ...CORS, 'Content-Type': 'application/json' });
    res.end(body);
  } catch (error) {
    console.error(error);
    res.writeHead(500, { ...CORS, 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: error.message }));
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`LearnVestor dev API on http://127.0.0.1:${PORT}`);
});
