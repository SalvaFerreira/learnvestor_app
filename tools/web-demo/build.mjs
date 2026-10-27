// Builds the browser demo into one static folder that any static host can serve:
//   Flutter web build (DEMO=true) + demo_api.js (demo API + PGlite) + pglite.wasm/.data
//
//   npm run build -- [--out <dir>] [--base-href path] [--skip-flutter]
//
// --out        target folder, emptied first (default: dist). Publishing to the website:
//              --out ../../../LearnVestor_Website/docs/demo --base-href LearnVestor_Website/demo
// --base-href  URL path the demo is served from (default: /). Slashes are optional, so Git Bash
//              on Windows does not turn it into a file path.
// --skip-flutter  reuse the existing apps/mobile/build/web (only rebuild the demo API)

import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { schemaFiles } from '../db-tests/harness.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MOBILE = join(HERE, '..', '..', 'apps', 'mobile');

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const out = resolve(HERE, option('--out', 'dist'));
const baseHref = `/${option('--base-href', '').replace(/^\/+|\/+$/g, '')}/`.replace('//', '/');
if (baseHref.includes(':')) throw new Error(`--base-href must be a URL path, got ${baseHref}`);

// Never empty a folder that is not a previous demo build.
if (existsSync(out) && readdirSync(out).length && !existsSync(join(out, 'demo_api.js'))) {
  throw new Error(`${out} is not empty and is not a previous demo build; refusing to overwrite it`);
}

// 1. Schema (stub + migrations + seeds) as a module, versioned by its content.
const files = schemaFiles();
const version = createHash('sha256').update(files.map((f) => f.name + f.sql).join('\0')).digest('hex').slice(0, 12);
mkdirSync(join(HERE, 'generated'), { recursive: true });
writeFileSync(join(HERE, 'generated', 'schema.mjs'), `export default ${JSON.stringify({ version, files })};\n`);
console.log(`schema ${version}: ${files.length} SQL files`);

// 2. Flutter web app in demo mode.
if (!args.includes('--skip-flutter')) {
  execSync(`flutter build web --release --dart-define=DEMO=true --base-href ${baseHref}`, { cwd: MOBILE, stdio: 'inherit' });
}

rmSync(out, { recursive: true, force: true });
cpSync(join(MOBILE, 'build', 'web'), out, { recursive: true });
// Flutter loads CanvasKit from Google's CDN (gstatic.com); the 27 MB local copy is never used.
rmSync(join(out, 'canvaskit'), { recursive: true, force: true });

// 3. Demo API bundle. PGlite's Node-only imports are never reached in the browser.
await build({
  entryPoints: [join(HERE, 'browser.mjs')],
  outfile: join(out, 'demo_api.js'),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'es2022',
  minify: true,
  external: ['fs', 'module', 'stream', 'stream/promises', 'zlib', 'path', 'url', 'crypto'],
  logLevel: 'warning',
});

// 4. PGlite runtime files, loaded by demo_api.js from the same folder.
const pglite = dirname(createRequire(join(HERE, 'package.json')).resolve('@electric-sql/pglite'));
for (const file of ['pglite.wasm', 'pglite.data']) cpSync(join(pglite, file), join(out, file));

// 5. Load demo_api.js before Flutter starts, so the API exists when the app makes its first call.
const indexPath = join(out, 'index.html');
const index = readFileSync(indexPath, 'utf8');
const bootstrap = /<script src="flutter_bootstrap\.js"[^>]*><\/script>/;
if (!bootstrap.test(index)) throw new Error('index.html: Flutter bootstrap script not found');
writeFileSync(indexPath, index.replace(bootstrap, (tag) => `<script src="demo_api.js"></script>\n  ${tag}`));

console.log(`Demo written to ${out} (served from ${baseHref})`);
