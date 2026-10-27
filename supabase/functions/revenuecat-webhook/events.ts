// Pure mapping from RevenueCat webhook events to the actions we take (unit-tested).
// Event reference: https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields

export interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id?: string;
  product_id?: string;
  entitlement_ids?: string[] | null;
  expiration_at_ms?: number | null;
  store?: string;
  environment?: string;
  transaction_id?: string;
  original_transaction_id?: string;
  transferred_from?: string[];
  transferred_to?: string[];
}

export type Source = 'app_store' | 'play_store' | 'stripe' | 'promotional';

export type Action =
  | {
    kind: 'entitlement';
    userId: string;
    source: Source;
    productId: string | null;
    active: boolean;
    expiresAt: string | null;
    originalTransactionId: string | null;
  }
  | { kind: 'gems'; userId: string; gems: number; source: Source; transactionId: string; productId: string }
  | { kind: 'resync'; userId: string }
  | { kind: 'ignore'; reason: string };

/** Consumable products sold in the stores (ids must match App Store Connect / Play Console). */
export const GEM_PRODUCTS: Record<string, number> = {
  gems_100: 100,
  gems_500: 500,
  gems_1200: 1200,
};

const PLUS = 'plus';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const GRANTING = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
  'SUBSCRIPTION_EXTENDED',
  'TEMPORARY_ENTITLEMENT_GRANT',
  'REFUND_REVERSED',
  // Auto-renew turned off (or refund): access lasts until expiration_at_ms, which
  // RevenueCat sets to the refund time when access is revoked immediately.
  'CANCELLATION',
]);

export function sourceFor(store: string | undefined): Source {
  switch (store) {
    case 'APP_STORE':
    case 'MAC_APP_STORE':
      return 'app_store';
    case 'PLAY_STORE':
      return 'play_store';
    case 'STRIPE':
    case 'RC_BILLING':
      return 'stripe';
    default:
      return 'promotional';
  }
}

export function classifyEvent(event: RevenueCatEvent): Action[] {
  if (event.type === 'TEST') return [{ kind: 'ignore', reason: 'test event' }];

  if (event.type === 'TRANSFER') {
    const users = [...(event.transferred_from ?? []), ...(event.transferred_to ?? [])].filter((u) => UUID.test(u));
    return users.length ? users.map((userId) => ({ kind: 'resync' as const, userId })) : [{ kind: 'ignore', reason: 'no known users' }];
  }

  const userId = event.app_user_id ?? '';
  if (!UUID.test(userId)) {
    // Anonymous RevenueCat ids ($RCAnonymousID:...) are never linked to an account.
    return [{ kind: 'ignore', reason: `unknown app_user_id ${userId}` }];
  }
  const source = sourceFor(event.store);
  const expiresAt = event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null;

  if (event.type === 'NON_RENEWING_PURCHASE') {
    const gems = GEM_PRODUCTS[event.product_id ?? ''];
    if (!gems || !event.transaction_id) return [{ kind: 'ignore', reason: `unknown product ${event.product_id}` }];
    return [{ kind: 'gems', userId, gems, source, transactionId: event.transaction_id, productId: event.product_id! }];
  }

  const touchesPlus = (event.entitlement_ids ?? []).includes(PLUS);
  if (!touchesPlus) return [{ kind: 'ignore', reason: 'event does not involve the plus entitlement' }];

  if (GRANTING.has(event.type)) {
    return [{
      kind: 'entitlement',
      userId,
      source,
      productId: event.product_id ?? null,
      active: true,
      expiresAt,
      originalTransactionId: event.original_transaction_id ?? null,
    }];
  }
  if (event.type === 'EXPIRATION') {
    return [{
      kind: 'entitlement',
      userId,
      source,
      productId: event.product_id ?? null,
      active: false,
      expiresAt,
      originalTransactionId: event.original_transaction_id ?? null,
    }];
  }
  // BILLING_ISSUE, SUBSCRIPTION_PAUSED...: access is still governed by expiration_at_ms.
  return [{ kind: 'ignore', reason: `no action for ${event.type}` }];
}
