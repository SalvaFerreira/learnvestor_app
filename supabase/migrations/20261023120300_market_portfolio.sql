-- Market data cache and the virtual portfolio.
--
-- Clients never talk to the market data provider: the market-data-sync Edge Function
-- refreshes quotes_latest/quotes_daily/fx_rates on a schedule (fixed cost, independent of
-- the number of users) and clients read the cache.
-- All portfolio money is VIRTUAL euros earned in lessons; it can never be bought or withdrawn.

create table public.instruments (
  symbol      text primary key check (symbol ~ '^[A-Z0-9.\-]{1,15}$'),
  name        text not null,
  exchange    text not null,
  currency    char(3) not null,
  sector      text not null check (sector in ('technology', 'finance', 'healthcare', 'consumer', 'energy', 'industrials', 'etf')),
  logo_url    text,
  popularity  int not null default 0,
  is_active   boolean not null default true
);

create table public.quotes_latest (
  symbol      text primary key references public.instruments (symbol) on delete cascade,
  price       numeric(18,6) not null check (price > 0),
  prev_close  numeric(18,6),
  change_pct  numeric(9,4),
  as_of       timestamptz not null,
  updated_at  timestamptz not null default now()
);

create table public.quotes_daily (
  symbol text not null references public.instruments (symbol) on delete cascade,
  day    date not null,
  close  numeric(18,6) not null check (close > 0),
  primary key (symbol, day)
);

-- Units of `currency` per 1 EUR (ECB reference rates). EUR itself is implicit (1).
create table public.fx_rates (
  currency     char(3) primary key,
  rate_per_eur numeric(18,8) not null check (rate_per_eur > 0),
  as_of        date not null
);

create table public.portfolios (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null unique references auth.users (id) on delete cascade,
  cash       numeric(14,2) not null default 0 check (cash >= 0),
  created_at timestamptz not null default now()
);

create table public.positions (
  portfolio_id  uuid not null references public.portfolios (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  symbol        text not null references public.instruments (symbol),
  quantity      numeric(18,6) not null check (quantity > 0),
  -- Total cost in EUR of the shares still held (average-cost method).
  cost_basis    numeric(18,6) not null check (cost_basis >= 0),
  updated_at    timestamptz not null default now(),
  primary key (portfolio_id, symbol)
);

create table public.trades (
  id              uuid primary key default gen_random_uuid(),
  portfolio_id    uuid not null references public.portfolios (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  symbol          text not null references public.instruments (symbol),
  side            text not null check (side in ('buy', 'sell')),
  quantity        numeric(18,6) not null check (quantity > 0),
  price           numeric(18,6) not null,
  currency        char(3) not null,
  fx_rate         numeric(18,8) not null,
  amount_eur      numeric(14,2) not null,
  realized_pnl    numeric(14,2),
  quote_as_of     timestamptz not null,
  idempotency_key uuid not null,
  executed_at     timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create table public.portfolio_snapshots (
  portfolio_id uuid not null references public.portfolios (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  day          date not null,
  cash         numeric(14,2) not null,
  value        numeric(14,2) not null,
  primary key (portfolio_id, day)
);

create index instruments_sector_idx on public.instruments (sector, popularity desc);
create index trades_user_idx on public.trades (user_id, executed_at desc);
create index positions_user_idx on public.positions (user_id);

alter table public.instruments enable row level security;
alter table public.quotes_latest enable row level security;
alter table public.quotes_daily enable row level security;
alter table public.fx_rates enable row level security;
alter table public.portfolios enable row level security;
alter table public.positions enable row level security;
alter table public.trades enable row level security;
alter table public.portfolio_snapshots enable row level security;

create policy "instruments: readable" on public.instruments for select to authenticated using (true);
create policy "quotes_latest: readable" on public.quotes_latest for select to authenticated using (true);
create policy "quotes_daily: readable" on public.quotes_daily for select to authenticated using (true);
create policy "fx_rates: readable" on public.fx_rates for select to authenticated using (true);
create policy "portfolios: read own" on public.portfolios for select to authenticated using (user_id = (select auth.uid()));
create policy "positions: read own" on public.positions for select to authenticated using (user_id = (select auth.uid()));
create policy "trades: read own" on public.trades for select to authenticated using (user_id = (select auth.uid()));
create policy "snapshots: read own" on public.portfolio_snapshots for select to authenticated using (user_id = (select auth.uid()));

create or replace function private.fx_rate(p_currency text)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case when p_currency = 'EUR' then 1::numeric
              else (select f.rate_per_eur from public.fx_rates f where f.currency = p_currency) end
$$;

-- Market value in EUR of the shares held (cash excluded). Positions without a quote or
-- FX rate are valued at cost so the total never silently drops to zero.
create or replace function private.holdings_value(p_portfolio uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(
           coalesce(round(p.quantity * q.price / private.fx_rate(i.currency), 2), round(p.cost_basis, 2))
         ), 0)
  from public.positions p
  join public.instruments i on i.symbol = p.symbol
  left join public.quotes_latest q on q.symbol = p.symbol
  where p.portfolio_id = p_portfolio
$$;

-- Daily point for the portfolio chart; scheduled by pg_cron (see *_cron.sql).
create or replace function private.snapshot_portfolios()
returns int
language plpgsql
set search_path = ''
as $$
declare
  v_count int;
begin
  insert into public.portfolio_snapshots (portfolio_id, user_id, day, cash, value)
  select p.id, p.user_id, current_date, p.cash, p.cash + private.holdings_value(p.id)
  from public.portfolios p
  on conflict (portfolio_id, day) do update
    set cash = excluded.cash, value = excluded.value;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Realtime price updates for open Explore/Portfolio screens (only where the publication exists).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.quotes_latest;
  end if;
end;
$$;
