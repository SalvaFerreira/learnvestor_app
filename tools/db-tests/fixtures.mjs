// Writes real RPC responses (from the migrations + seeds running on PGlite) to
// apps/mobile/test/fixtures, where the Flutter contract test parses them with the app's
// models. Run after changing an RPC's output:  npm run fixtures
import { randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { backdateAttempt, correctAnswers, createDb, createUser, rpc } from './harness.mjs';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'apps', 'mobile', 'test', 'fixtures');
mkdirSync(OUT, { recursive: true });
const save = (name, data) => writeFileSync(join(OUT, `${name}.json`), `${JSON.stringify(data, null, 2)}\n`);

const db = await createDb();
const uid = await createUser(db, { locale: 'pt', timezone: 'Europe/Lisbon', country: 'PT' });

const lesson = await rpc(db, uid, 'start_lesson', { p_lesson_id: 'what-is-a-bank', p_locale: 'pt' });
save('start_lesson', lesson);
await rpc(db, uid, 'lose_heart', { p_attempt_id: lesson.attempt_id }).then((h) => save('lose_heart', h));
await backdateAttempt(db, lesson.attempt_id);
const answers = correctAnswers(lesson);
answers['deposit-guarantee'] = false;
save('complete_lesson', await rpc(db, uid, 'complete_lesson', { p_attempt_id: lesson.attempt_id, p_answers: answers }));

await rpc(db, uid, 'place_trade', { p_symbol: 'AAPL', p_side: 'buy', p_amount_eur: 50, p_idempotency_key: randomUUID() });
await rpc(db, uid, 'place_trade', { p_symbol: 'GALP.LS', p_side: 'buy', p_quantity: 1.5, p_idempotency_key: randomUUID() });

const practice = await rpc(db, uid, 'start_practice', { p_locale: 'pt' });
save('start_practice', practice);
await db.query(`update public.practice_sessions set started_at = now() - interval '5 minutes' where id = $1`, [practice.attempt_id]);
save('complete_practice', await rpc(db, uid, 'complete_practice', { p_session_id: practice.attempt_id, p_answers: correctAnswers(practice) }));

save('get_my_state', await rpc(db, uid, 'get_my_state'));
save('get_learning_path', await rpc(db, uid, 'get_learning_path', { p_locale: 'pt' }));
save('get_portfolio', await rpc(db, uid, 'get_portfolio'));
save('get_my_achievements', await rpc(db, uid, 'get_my_achievements', { p_locale: 'pt' }));

console.log(`Fixtures written to ${OUT}`);
