// Curriculum coverage: which lessons are planned, drafted or reviewed, unit by unit.
//
//   node scripts/status.mjs

import { coverage, loadContent } from './lib/content.mjs';

const rows = coverage(loadContent());
const pad = (s, n) => String(s).padEnd(n);
console.log(`${pad('track', 12)}${pad('unit', 26)}${pad('reviewed', 10)}${pad('draft', 8)}${pad('planned', 9)}next to draft`);
for (const r of rows) {
  console.log(`${pad(r.track, 12)}${pad(r.unit, 26)}${pad(r.reviewed, 10)}${pad(r.draft, 8)}${pad(r.planned, 9)}${r.next.slice(0, 3).join(', ')}`);
}
const total = rows.reduce((t, r) => t + r.reviewed + r.draft + r.planned, 0);
const reviewed = rows.reduce((t, r) => t + r.reviewed, 0);
const drafted = rows.reduce((t, r) => t + r.draft, 0);
console.log(`\n${reviewed}/${total} reviewed, ${drafted} waiting for review, ${total - reviewed - drafted} planned.`);
