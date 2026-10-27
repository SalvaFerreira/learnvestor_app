-- Monetization: entitlements (subscriptions) and purchases (consumables).
--
-- Source of truth is the payment provider. Rows here are written only by webhook handlers
-- (Edge Functions running as service_role) through the svc_* functions; clients can read
-- their own rows but never write them.

create table public.entitlements (
  id                      bigint generated always as identity primary key,
  user_id                 uuid not null references auth.users (id) on delete cascade,
  entitlement             text not null check (entitlement in ('plus')),
  source                  text not null check (source in ('app_store', 'play_store', 'stripe', 'promotional', 'b2b')),
  product_id              text,
  is_active               boolean not null default true,
  expires_at              timestamptz,
  original_transaction_id text,
  updated_at              timestamptz not null default now(),
  unique (user_id, entitlement)
);

create table public.purchases (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  source         text not null,
  transaction_id text not null unique,
  product_id     text not null,
  kind           text not null check (kind in ('gems')),
  quantity       int not null check (quantity > 0),
  created_at     timestamptz not null default now()
);

-- Idempotency log for incoming webhooks (providers retry and may deliver twice).
create table public.webhook_events (
  id          text primary key,
  source      text not null,
  event_type  text not null,
  payload     jsonb not null,
  received_at timestamptz not null default now()
);

create index purchases_user_idx on public.purchases (user_id, created_at desc);

alter table public.entitlements enable row level security;
alter table public.purchases enable row level security;
alter table public.webhook_events enable row level security;

create policy "entitlements: read own" on public.entitlements
  for select to authenticated using (user_id = (select auth.uid()));
create policy "purchases: read own" on public.purchases
  for select to authenticated using (user_id = (select auth.uid()));
-- webhook_events: service_role only (bypasses RLS), no policies.

create trigger entitlements_touch before update on public.entitlements
  for each row execute function private.touch_updated_at();

create or replace function private.has_plus(p_user uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = p_user
      and e.entitlement = 'plus'
      and e.is_active
      and (e.expires_at is null or e.expires_at > now())
  )
$$;
