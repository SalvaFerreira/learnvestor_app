// RevenueCat webhook: the only writer of entitlements (LearnVestor Plus) and gem purchases.
//
// Setup (RevenueCat dashboard > Integrations > Webhooks):
//   URL:                  https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
//   Authorization header: the value of REVENUECAT_WEBHOOK_AUTH
// The app calls Purchases.logIn(<supabase user id>), so app_user_id is our user UUID.
//
// Env: REVENUECAT_WEBHOOK_AUTH, optional REVENUECAT_API_KEY (secret v1 key, used to resync
// subscribers on TRANSFER events).

import { json, safeEqual } from '../_shared/http.ts';
import { adminClient } from '../_shared/supabase.ts';
import { classifyEvent, type RevenueCatEvent, sourceFor } from './events.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (!safeEqual(req.headers.get('authorization'), Deno.env.get('REVENUECAT_WEBHOOK_AUTH'))) {
    return json({ error: 'unauthorized' }, 401);
  }

  let event: RevenueCatEvent;
  try {
    event = (await req.json()).event;
    if (!event?.id || !event?.type) throw new Error('missing event');
  } catch {
    return json({ error: 'invalid_payload' }, 400);
  }

  const db = adminClient();

  // Providers retry on non-2xx and may deliver twice: skip events already processed.
  const { data: seen } = await db.from('webhook_events').select('id').eq('id', event.id).maybeSingle();
  if (seen) return json({ status: 'duplicate' });

  const actions = classifyEvent(event);
  try {
    for (const action of actions) {
      switch (action.kind) {
        case 'entitlement': {
          const { error } = await db.rpc('svc_apply_entitlement', {
            p_user: action.userId,
            p_entitlement: 'plus',
            p_source: action.source,
            p_product_id: action.productId,
            p_is_active: action.active,
            p_expires_at: action.expiresAt,
            p_original_transaction_id: action.originalTransactionId,
          });
          if (error) throw error;
          break;
        }
        case 'gems': {
          const { error } = await db.rpc('svc_credit_gems', {
            p_user: action.userId,
            p_gems: action.gems,
            p_source: action.source,
            p_transaction_id: action.transactionId,
            p_product_id: action.productId,
          });
          if (error) throw error;
          break;
        }
        case 'resync':
          await resyncSubscriber(db, action.userId);
          break;
        case 'ignore':
          console.log(`revenuecat ${event.type} ignored: ${action.reason}`);
          break;
      }
    }
  } catch (error) {
    // Non-2xx makes RevenueCat retry later; every action above is idempotent.
    console.error(`revenuecat ${event.type} ${event.id} failed`, error);
    return json({ error: 'processing_failed' }, 500);
  }

  await db.from('webhook_events').insert({
    id: event.id,
    source: 'revenuecat',
    event_type: event.type,
    payload: event,
  });
  return json({ status: 'ok', actions: actions.map((a) => a.kind) });
});

/** Reads the subscriber's current entitlement from the RevenueCat API (source of truth). */
async function resyncSubscriber(db: ReturnType<typeof adminClient>, userId: string): Promise<void> {
  const apiKey = Deno.env.get('REVENUECAT_API_KEY');
  if (!apiKey) {
    console.warn(`cannot resync ${userId}: REVENUECAT_API_KEY not set`);
    return;
  }
  const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!res.ok) throw new Error(`RevenueCat subscriber lookup failed with ${res.status}`);
  const { subscriber } = await res.json();
  const plus = subscriber?.entitlements?.plus;
  const store: string | undefined = subscriber?.subscriptions?.[plus?.product_identifier]?.store;
  const { error } = await db.rpc('svc_apply_entitlement', {
    p_user: userId,
    p_entitlement: 'plus',
    p_source: sourceFor(store?.toUpperCase()),
    p_product_id: plus?.product_identifier ?? null,
    p_is_active: Boolean(plus) && (!plus.expires_date || new Date(plus.expires_date) > new Date()),
    p_expires_at: plus?.expires_date ?? null,
    p_original_transaction_id: null,
  });
  if (error) throw error;
}
