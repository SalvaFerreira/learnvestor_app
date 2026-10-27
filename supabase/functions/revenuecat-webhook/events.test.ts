import { assertEquals } from 'jsr:@std/assert@1';
import { classifyEvent } from './events.ts';

const user = '6f1c2a9e-3b4d-4e5f-8a7b-1c2d3e4f5a6b';
const base = { id: 'evt', app_user_id: user, store: 'APP_STORE', product_id: 'plus_monthly', entitlement_ids: ['plus'] };

Deno.test('initial purchase grants plus until expiration', () => {
  const [action] = classifyEvent({ ...base, type: 'INITIAL_PURCHASE', expiration_at_ms: Date.UTC(2026, 11, 1) });
  assertEquals(action, {
    kind: 'entitlement',
    userId: user,
    source: 'app_store',
    productId: 'plus_monthly',
    active: true,
    expiresAt: '2026-12-01T00:00:00.000Z',
    originalTransactionId: null,
  });
});

Deno.test('expiration revokes plus', () => {
  const [action] = classifyEvent({ ...base, type: 'EXPIRATION', store: 'PLAY_STORE' });
  assertEquals(action.kind === 'entitlement' && action.active, false);
  assertEquals(action.kind === 'entitlement' && action.source, 'play_store');
});

Deno.test('gem packs are credited once per transaction id', () => {
  const [action] = classifyEvent({ ...base, type: 'NON_RENEWING_PURCHASE', product_id: 'gems_500', transaction_id: 't1', entitlement_ids: [] });
  assertEquals(action, { kind: 'gems', userId: user, gems: 500, source: 'app_store', transactionId: 't1', productId: 'gems_500' });
});

Deno.test('anonymous ids and unknown products are ignored', () => {
  assertEquals(classifyEvent({ ...base, type: 'INITIAL_PURCHASE', app_user_id: '$RCAnonymousID:abc' })[0].kind, 'ignore');
  assertEquals(classifyEvent({ ...base, type: 'NON_RENEWING_PURCHASE', product_id: 'mystery', transaction_id: 't' })[0].kind, 'ignore');
});

Deno.test('transfers resync both accounts', () => {
  const other = '0e1d2c3b-4a59-4687-9a0b-c1d2e3f4a5b6';
  const actions = classifyEvent({ id: 'evt', type: 'TRANSFER', transferred_from: [user], transferred_to: [other] });
  assertEquals(actions, [{ kind: 'resync', userId: user }, { kind: 'resync', userId: other }]);
});
