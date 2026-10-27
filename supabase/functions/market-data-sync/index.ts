// Refreshes the market data cache. Called every 5 minutes on weekdays by pg_cron
// (see migrations/*_cron.sql), authenticated with the shared CRON_SECRET.
//
// Cost is fixed: it refreshes the curated instrument list, oldest quote first, regardless
// of how many users are online. Clients only ever read the cached tables.
//
// Env: CRON_SECRET, FINNHUB_API_KEY, optional MARKET_SYNC_BATCH (default 60) and
// MARKET_SYNC_DELAY_MS (default 1100, keeps under 60 requests/minute).

import { json, requireEnv, safeEqual } from '../_shared/http.ts';
import { fetchEcbRates, FinnhubProvider, type MarketDataProvider, RateLimitError } from '../_shared/market.ts';
import { adminClient } from '../_shared/supabase.ts';

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (!safeEqual(req.headers.get('x-cron-secret'), Deno.env.get('CRON_SECRET'))) {
    return json({ error: 'unauthorized' }, 401);
  }

  const db = adminClient();
  const provider: MarketDataProvider = new FinnhubProvider(requireEnv('FINNHUB_API_KEY'));
  const batch = Number(Deno.env.get('MARKET_SYNC_BATCH') ?? 60);
  const delayMs = Number(Deno.env.get('MARKET_SYNC_DELAY_MS') ?? 1100);
  const summary = { fx: 'fresh', updated: 0, unsupported: [] as string[], failed: [] as string[], rateLimited: false };

  // 1. FX rates. The ECB publishes once per working day (~16:00 CET); until today's
  //    rates exist we re-check on each run (one small XML request).
  const { data: usd } = await db.from('fx_rates').select('as_of').eq('currency', 'USD').maybeSingle();
  const today = new Date().toISOString().slice(0, 10);
  if (!usd || usd.as_of < today) {
    try {
      const { asOf, rates } = await fetchEcbRates();
      const rows = Object.entries(rates).map(([currency, rate]) => ({ currency, rate_per_eur: rate, as_of: asOf }));
      const { error } = await db.from('fx_rates').upsert(rows);
      if (error) throw error;
      summary.fx = `updated ${asOf}`;
    } catch (error) {
      console.error('fx update failed', error);
      summary.fx = 'failed';
    }
  }

  // 2. Quotes, stalest first.
  const [{ data: instruments, error: iErr }, { data: quotes, error: qErr }] = await Promise.all([
    db.from('instruments').select('symbol, logo_url').eq('is_active', true),
    db.from('quotes_latest').select('symbol, updated_at'),
  ]);
  if (iErr || qErr) return json({ error: 'database_error', detail: (iErr ?? qErr)?.message }, 500);

  const lastUpdate = new Map((quotes ?? []).map((q) => [q.symbol, new Date(q.updated_at).getTime()]));
  const queue = (instruments ?? [])
    .sort((a, b) => (lastUpdate.get(a.symbol) ?? 0) - (lastUpdate.get(b.symbol) ?? 0))
    .slice(0, batch);

  for (const instrument of queue) {
    try {
      const quote = await provider.quote(instrument.symbol);
      if (!quote) {
        summary.unsupported.push(instrument.symbol);
      } else {
        const asOf = quote.asOf.toISOString();
        const { error: upErr } = await db.from('quotes_latest').upsert({
          symbol: quote.symbol,
          price: quote.price,
          prev_close: quote.prevClose,
          change_pct: quote.changePct,
          as_of: asOf,
          updated_at: new Date().toISOString(),
        });
        if (upErr) throw upErr;
        await db.from('quotes_daily').upsert({ symbol: quote.symbol, day: asOf.slice(0, 10), close: quote.price });
        summary.updated++;

        if (!instrument.logo_url) {
          await sleep(delayMs);
          const logo = await provider.logo(instrument.symbol).catch(() => null);
          if (logo) await db.from('instruments').update({ logo_url: logo }).eq('symbol', instrument.symbol);
        }
      }
    } catch (error) {
      if (error instanceof RateLimitError) {
        summary.rateLimited = true;
        break;
      }
      console.error(`quote ${instrument.symbol} failed`, error);
      summary.failed.push(instrument.symbol);
    }
    await sleep(delayMs);
  }

  console.log('market-data-sync', JSON.stringify(summary));
  return json(summary);
});
