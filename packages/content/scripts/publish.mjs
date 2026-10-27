// Publishes REVIEWED content to a database (drafts are never published).
//
//   DATABASE_URL=postgresql://... node scripts/publish.mjs
//
// Use the connection string of the target Supabase project (Settings > Database). The SQL
// runs in a single transaction and refuses to overwrite a published lesson version whose
// content changed, so it is safe to run on every deploy.

import pg from 'pg';
import { compileSql, loadContent, validateContent } from './lib/content.mjs';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL is not set.');
  process.exit(1);
}

const content = loadContent();
const errors = validateContent(content);
if (errors.length) {
  console.error(`Refusing to publish invalid content:\n  - ${errors.join('\n  - ')}`);
  process.exit(1);
}
const reviewed = content.lessons.filter(({ data }) => data.status === 'reviewed').length;
if (reviewed === 0) {
  console.error('No reviewed lessons to publish. Review drafts first (status: "reviewed" + review + sources).');
  process.exit(1);
}

// TLS is configured through the connection string (e.g. ?sslmode=verify-full with
// PGSSLROOTCERT pointing to the Supabase CA certificate from the dashboard).
const client = new pg.Client({ connectionString: url });
try {
  await client.connect();
  await client.query(compileSql(content, { reviewedOnly: true }));
  console.log(`Published ${reviewed} reviewed lessons.`);
} catch (error) {
  console.error(`Publishing failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await client.end();
}
