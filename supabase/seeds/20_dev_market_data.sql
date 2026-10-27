-- DEV ONLY: sample prices so the app works locally without a market data API key.
-- These are NOT real quotes. In staging/production the market-data-sync function
-- overwrites them, and seeds are never applied to remote databases.

insert into public.fx_rates (currency, rate_per_eur, as_of) values
  ('USD', 1.08, current_date)
on conflict (currency) do update set rate_per_eur = excluded.rate_per_eur, as_of = excluded.as_of;

insert into public.quotes_latest (symbol, price, prev_close, change_pct, as_of)
select v.symbol, v.price, round(v.price / (1 + v.change_pct / 100), 6), v.change_pct, now()
from (values
  ('AAPL', 238.99, 0.85), ('MSFT', 510.02, -0.42), ('GOOGL', 245.10, 1.12), ('AMZN', 228.40, 0.30),
  ('NVDA', 182.75, 2.05), ('META', 735.20, -1.10), ('ASML.AS', 860.00, 0.65), ('SAP.DE', 245.80, -0.20),
  ('JPM', 305.40, 0.40), ('V', 345.10, 0.15), ('MA', 575.60, 0.22), ('BAC', 50.20, -0.35),
  ('GS', 780.30, 0.90), ('BCP.LS', 0.72, 1.40), ('JNJ', 185.50, -0.10), ('LLY', 820.00, 1.75),
  ('UNH', 340.20, -2.10), ('PFE', 25.40, 0.05), ('NVO', 55.80, -0.80), ('KO', 68.90, 0.12),
  ('MCD', 305.70, -0.25), ('NKE', 70.10, 1.05), ('TSLA', 440.50, 3.20), ('SBUX', 84.30, -0.60),
  ('JMT.LS', 20.50, 0.35), ('XOM', 114.20, -0.45), ('CVX', 155.90, -0.30), ('GALP.LS', 17.10, 0.80),
  ('EDP.LS', 3.85, 0.25), ('CAT', 520.40, 1.30), ('GE', 300.10, 0.70), ('AIR.PA', 205.60, 0.55),
  ('SPY', 665.30, 0.45), ('QQQ', 600.20, 0.70), ('VT', 138.40, 0.38), ('VTI', 325.60, 0.42)
) as v(symbol, price, change_pct)
on conflict (symbol) do update
  set price = excluded.price, prev_close = excluded.prev_close, change_pct = excluded.change_pct, as_of = excluded.as_of;
