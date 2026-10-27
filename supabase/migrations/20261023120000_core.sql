-- Core: schemas, shared helpers, game configuration and profiles.
--
-- Conventions used across all migrations:
--   * public  : tables and RPCs reachable through the Supabase API. Every table has RLS on.
--   * private : internal helpers and config. API roles have no usage on this schema.
--   * Grants to anon/authenticated are NOT given here; they live in the *_api_grants.sql
--     migration so the full API surface can be reviewed in one place.
--   * Functions that mutate game state are SECURITY DEFINER with an empty search_path and
--     fully qualified names.

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Single-row table with every tunable game rule, so operations can adjust the economy
-- with a plain UPDATE instead of a migration.
create table private.game_config (
  id                       boolean primary key default true check (id),
  max_hearts               int     not null default 6    check (max_hearts > 0),
  heart_regen_minutes      int     not null default 60   check (heart_regen_minutes > 0),
  starting_cash            numeric(14,2) not null default 100.00,
  daily_xp_cap             int     not null default 1500,
  perfect_lesson_bonus_xp  int     not null default 5,
  replay_xp_divisor        int     not null default 3    check (replay_xp_divisor > 0),
  min_seconds_per_exercise int     not null default 2,
  attempt_ttl_minutes      int     not null default 180,
  max_attempts_per_hour    int     not null default 60,
  refill_hearts_gem_cost   int     not null default 50,
  quote_max_age_hours      int     not null default 120,
  min_trade_eur            numeric(14,2) not null default 1.00,
  max_trades_per_hour      int     not null default 120
);
insert into private.game_config default values;

create or replace function private.config()
returns private.game_config
language sql
stable
set search_path = ''
as $$ select * from private.game_config limit 1 $$;

create or replace function private.is_valid_timezone(p_tz text)
returns boolean
language sql
stable
set search_path = ''
as $$ select exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) $$;

-- Profiles ------------------------------------------------------------------------------

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text check (char_length(display_name) <= 40),
  country_code        char(2) check (country_code ~ '^[A-Z]{2}$'),
  locale              text not null default 'en' check (locale in ('en', 'pt')),
  timezone            text not null default 'UTC',
  timezone_changed_at timestamptz,
  display_currency    char(3) not null default 'EUR',
  daily_goal_xp       int not null default 30 check (daily_goal_xp in (10, 20, 30, 50)),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: read own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Timezone drives streak days, so changing it is validated and throttled to once per day
-- (stops "moving" to another timezone to rescue a streak).
create or replace function private.validate_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.timezone is distinct from old.timezone then
    if not private.is_valid_timezone(new.timezone) then
      raise exception 'invalid_timezone' using errcode = '22023';
    end if;
    if old.timezone_changed_at is not null and old.timezone_changed_at > now() - interval '24 hours' then
      raise exception 'timezone_change_too_soon' using errcode = '22023';
    end if;
    new.timezone_changed_at := now();
  end if;
  return new;
end;
$$;

create trigger profiles_validate before update on public.profiles
  for each row execute function private.validate_profile();

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();
