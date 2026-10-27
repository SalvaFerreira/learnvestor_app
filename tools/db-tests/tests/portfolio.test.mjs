// Virtual trading: server-side prices, FX, cash checks and idempotency.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, describe, test } from 'node:test';
import { createDb, createUser, onboard, rpc, sql } from '../harness.mjs';

let db;
let n = 0;

async function investor() {
  const uid = await createUser(db);
  await onboard(db, uid, `investor${++n}`);
  return uid;
}

const trade = (uid, args) => rpc(db, uid, 'place_trade', { p_idempotency_key: randomUUID(), ...args });

before(async () => {
  db = await createDb();
  // Deterministic prices for the assertions below.
  await sql(db, `update public.fx_rates set rate_per_eur = 1.25 where currency = 'USD'`);
  await sql(db, `update public.quotes_latest set price = 50, as_of = now() where symbol = 'AAPL'`);
  await sql(db, `update public.quotes_latest set price = 20, as_of = now() where symbol = 'GALP.LS'`);
});

describe('buying', () => {
  test('buys by EUR amount at the server price converted from USD', async () => {
    const uid = await investor();
    const result = await trade(uid, { p_symbol: 'aapl', p_side: 'buy', p_amount_eur: 40 });
    // 50 USD / 1.25 = 40 EUR per share -> exactly 1 share
    assert.equal(Number(result.trade.quantity), 1);
    assert.equal(Number(result.trade.amount_eur), 40);
    assert.equal(Number(result.cash), 60);
    assert.deepEqual(result.new_achievements, ['first_trade']);
  });

  test('buys fractional quantities', async () => {
    const uid = await investor();
    const result = await trade(uid, { p_symbol: 'GALP.LS', p_side: 'buy', p_quantity: 0.5 });
    assert.equal(Number(result.trade.amount_eur), 10);
    assert.equal(Number(result.cash), 90);
  });

  test('rejects buying more than the available cash', async () => {
    const uid = await investor();
    await assert.rejects(trade(uid, { p_symbol: 'AAPL', p_side: 'buy', p_quantity: 3 }), /insufficient_cash/);
  });

  test('rejects tiny, invalid or unknown orders', async () => {
    const uid = await investor();
    await assert.rejects(trade(uid, { p_symbol: 'AAPL', p_side: 'buy', p_amount_eur: 0.5 }), /amount_too_small/);
    await assert.rejects(trade(uid, { p_symbol: 'AAPL', p_side: 'buy', p_quantity: -1 }), /invalid_quantity/);
    await assert.rejects(trade(uid, { p_symbol: 'AAPL', p_side: 'buy', p_quantity: 0.0000001 }), /invalid_quantity/);
    await assert.rejects(trade(uid, { p_symbol: 'AAPL', p_side: 'short' }), /invalid_side/);
    await assert.rejects(trade(uid, { p_symbol: 'NOPE', p_side: 'buy', p_quantity: 1 }), /unknown_symbol/);
  });

  test('refuses to trade on stale quotes', async () => {
    const uid = await investor();
    await sql(db, `update public.quotes_latest set as_of = now() - interval '10 days' where symbol = 'KO'`);
    await assert.rejects(trade(uid, { p_symbol: 'KO', p_side: 'buy', p_amount_eur: 10 }), /quote_unavailable/);
  });

  test('retried requests with the same idempotency key execute once', async () => {
    const uid = await investor();
    const key = randomUUID();
    const first = await rpc(db, uid, 'place_trade', { p_symbol: 'AAPL', p_side: 'buy', p_quantity: 1, p_idempotency_key: key });
    const retry = await rpc(db, uid, 'place_trade', { p_symbol: 'AAPL', p_side: 'buy', p_quantity: 1, p_idempotency_key: key });
    assert.equal(retry.replayed, true);
    assert.equal(retry.trade.id, first.trade.id);
    const p = await rpc(db, uid, 'get_portfolio');
    assert.equal(Number(p.cash), 60);
  });
});

describe('selling', () => {
  test('partial sell reduces cost basis proportionally and realizes P&L', async () => {
    const uid = await investor();
    await trade(uid, { p_symbol: 'GALP.LS', p_side: 'buy', p_quantity: 2 }); // 40 EUR
    await sql(db, `update public.quotes_latest set price = 30 where symbol = 'GALP.LS'`);
    const sell = await trade(uid, { p_symbol: 'GALP.LS', p_side: 'sell', p_quantity: 1 });
    assert.equal(Number(sell.trade.amount_eur), 30);
    assert.equal(Number(sell.trade.realized_pnl), 10);

    const p = await rpc(db, uid, 'get_portfolio');
    assert.equal(p.positions.length, 1);
    assert.equal(Number(p.positions[0].quantity), 1);
    assert.equal(Number(p.positions[0].cost_basis_eur), 20);
    assert.equal(Number(p.cash), 90);
    assert.equal(Number(p.total_value), 120);
    await sql(db, `update public.quotes_latest set price = 20 where symbol = 'GALP.LS'`);
  });

  test('selling everything closes the position; cannot oversell', async () => {
    const uid = await investor();
    await trade(uid, { p_symbol: 'GALP.LS', p_side: 'buy', p_quantity: 1 });
    await assert.rejects(trade(uid, { p_symbol: 'GALP.LS', p_side: 'sell', p_quantity: 2 }), /insufficient_shares/);
    await trade(uid, { p_symbol: 'GALP.LS', p_side: 'sell', p_quantity: 1 });
    const p = await rpc(db, uid, 'get_portfolio');
    assert.equal(p.positions.length, 0);
    assert.equal(Number(p.cash), 100);
  });
});

describe('portfolio views', () => {
  test('state and portfolio report the same total value', async () => {
    const uid = await investor();
    await trade(uid, { p_symbol: 'AAPL', p_side: 'buy', p_quantity: 1 });
    await sql(db, `update public.quotes_latest set price = 62.5 where symbol = 'AAPL'`); // 50 EUR
    const s = await rpc(db, uid, 'get_my_state');
    const p = await rpc(db, uid, 'get_portfolio');
    assert.equal(Number(s.portfolio.total_value), 110);
    assert.equal(Number(p.total_value), 110);
    assert.equal(p.history.length, 1, 'signup snapshot');
    await sql(db, `update public.quotes_latest set price = 50 where symbol = 'AAPL'`);
  });

  test('daily snapshot job records every portfolio', async () => {
    const [{ count }] = await sql(db, 'select private.snapshot_portfolios() as count');
    const [{ portfolios }] = await sql(db, 'select count(*)::int as portfolios from public.portfolios');
    assert.equal(count, portfolios);
  });
});
