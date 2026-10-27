-- Gamification state. The server is authoritative: clients read these tables but every
-- change goes through RPCs (see *_rpc.sql). Balances change together with an append-only
-- ledger row (xp_events / currency_ledger) for auditing and anti-cheat analysis.

create table public.user_stats (
  user_id           uuid primary key references auth.users (id) on delete cascade,
  xp                bigint not null default 0 check (xp >= 0),
  level             int not null default 1 check (level >= 1),
  gems              int not null default 0 check (gems >= 0),
  hearts            int not null default 0 check (hearts >= 0),
  -- Point in time from which heart regeneration is counted.
  hearts_updated_at timestamptz not null default now(),
  streak_current    int not null default 0 check (streak_current >= 0),
  streak_longest    int not null default 0 check (streak_longest >= 0),
  -- Last day (in the user's timezone) with a completed lesson.
  streak_last_day   date,
  lessons_completed int not null default 0,
  coins_earned      numeric(14,2) not null default 0,
  updated_at        timestamptz not null default now()
);

create table public.lesson_attempts (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  lesson_id        text not null references public.lessons (id) on delete cascade,
  version          int not null,
  locale           text not null,
  status           text not null default 'started' check (status in ('started', 'completed', 'failed', 'expired')),
  hearts_lost      int not null default 0,
  correct          int,
  mistakes         int,
  stars            int check (stars between 1 and 3),
  xp_awarded       int,
  coins_awarded    numeric(12,2),
  answers          jsonb,
  started_at       timestamptz not null default now(),
  completed_at     timestamptz,
  foreign key (lesson_id, version) references public.lesson_versions (lesson_id, version)
);

create table public.lesson_progress (
  user_id            uuid not null references auth.users (id) on delete cascade,
  lesson_id          text not null references public.lessons (id) on delete cascade,
  best_stars         int not null check (best_stars between 1 and 3),
  times_completed    int not null default 1,
  first_completed_at timestamptz not null default now(),
  last_completed_at  timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table public.xp_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  amount     int not null,
  reason     text not null,
  ref_id     text,
  -- Day in the user's timezone (daily goal, daily cap).
  local_date date not null,
  created_at timestamptz not null default now()
);

create table public.currency_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  currency   text not null check (currency in ('coins', 'gems')),
  amount     numeric(14,2) not null,
  reason     text not null,
  ref_id     text,
  created_at timestamptz not null default now()
);

create table public.achievements (
  id         text primary key check (id ~ '^[a-z0-9_]+$'),
  metric     text not null check (metric in ('lessons_completed', 'streak', 'level', 'xp', 'trades', 'positions')),
  threshold  int not null check (threshold > 0),
  gem_reward int not null default 0,
  icon       text not null,
  position   int not null
);

create table public.achievement_translations (
  achievement_id text not null references public.achievements (id) on delete cascade,
  locale         text not null check (locale in ('en', 'pt')),
  title          text not null,
  description    text not null,
  primary key (achievement_id, locale)
);

create table public.user_achievements (
  user_id        uuid not null references auth.users (id) on delete cascade,
  achievement_id text not null references public.achievements (id) on delete cascade,
  unlocked_at    timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create index lesson_attempts_user_idx on public.lesson_attempts (user_id, started_at desc);
create index xp_events_user_day_idx on public.xp_events (user_id, local_date);
create index xp_events_created_idx on public.xp_events (created_at, user_id);
create index currency_ledger_user_idx on public.currency_ledger (user_id, created_at desc);

alter table public.user_stats enable row level security;
alter table public.lesson_attempts enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.xp_events enable row level security;
alter table public.currency_ledger enable row level security;
alter table public.achievements enable row level security;
alter table public.achievement_translations enable row level security;
alter table public.user_achievements enable row level security;

create policy "user_stats: read own" on public.user_stats for select to authenticated using (user_id = (select auth.uid()));
create policy "lesson_attempts: read own" on public.lesson_attempts for select to authenticated using (user_id = (select auth.uid()));
create policy "lesson_progress: read own" on public.lesson_progress for select to authenticated using (user_id = (select auth.uid()));
create policy "xp_events: read own" on public.xp_events for select to authenticated using (user_id = (select auth.uid()));
create policy "currency_ledger: read own" on public.currency_ledger for select to authenticated using (user_id = (select auth.uid()));
create policy "achievements: readable" on public.achievements for select to authenticated using (true);
create policy "achievement_translations: readable" on public.achievement_translations for select to authenticated using (true);
create policy "user_achievements: read own" on public.user_achievements for select to authenticated using (user_id = (select auth.uid()));

create trigger user_stats_touch before update on public.user_stats
  for each row execute function private.touch_updated_at();

-- Levels ---------------------------------------------------------------------------------
-- Reaching level L needs 100*(L-1) + 25*(L-1)*(L-2) XP: 100 XP for level 2, then each
-- level costs 50 XP more than the previous one.

create or replace function private.xp_for_level(p_level int)
returns bigint
language sql
immutable
set search_path = ''
as $$ select (100 * (p_level - 1) + 25 * (p_level - 1) * (p_level - 2))::bigint $$;

create or replace function private.level_for_xp(p_xp bigint)
returns int
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_level int := 1;
begin
  while private.xp_for_level(v_level + 1) <= p_xp loop
    v_level := v_level + 1;
  end loop;
  return v_level;
end;
$$;

-- Hearts ---------------------------------------------------------------------------------
-- Regeneration is computed lazily from (hearts, hearts_updated_at): no per-user cron.

create or replace function private.effective_hearts(
  p_hearts int, p_updated_at timestamptz, out hearts int, out next_heart_at timestamptz)
language plpgsql
stable
set search_path = ''
as $$
declare
  c private.game_config := private.config();
  v_gain int;
begin
  if p_hearts >= c.max_hearts then
    hearts := c.max_hearts;
    next_heart_at := null;
    return;
  end if;
  v_gain := floor(extract(epoch from now() - p_updated_at) / (c.heart_regen_minutes * 60))::int;
  hearts := least(c.max_hearts, p_hearts + greatest(v_gain, 0));
  if hearts < c.max_hearts then
    next_heart_at := p_updated_at + make_interval(mins => (greatest(v_gain, 0) + 1) * c.heart_regen_minutes);
  end if;
end;
$$;

-- Persists regenerated hearts. Caller must hold the user_stats row lock.
create or replace function private.sync_hearts(p_user uuid)
returns int
language plpgsql
set search_path = ''
as $$
declare
  c private.game_config := private.config();
  s public.user_stats;
  e record;
  v_gain int;
begin
  select * into s from public.user_stats where user_id = p_user;
  select * into e from private.effective_hearts(s.hearts, s.hearts_updated_at);
  if e.hearts <> s.hearts then
    v_gain := e.hearts - s.hearts;
    update public.user_stats
       set hearts = e.hearts,
           hearts_updated_at = case when e.hearts >= c.max_hearts then now()
                                    else s.hearts_updated_at + make_interval(mins => v_gain * c.heart_regen_minutes) end
     where user_id = p_user;
  end if;
  return e.hearts;
end;
$$;

-- Removes up to p_count hearts and returns how many were actually removed.
-- Caller must hold the user_stats row lock.
create or replace function private.deduct_hearts(p_user uuid, p_count int)
returns int
language plpgsql
set search_path = ''
as $$
declare
  c private.game_config := private.config();
  v_hearts int := private.sync_hearts(p_user);
  v_removed int := least(v_hearts, greatest(p_count, 0));
begin
  if v_removed > 0 then
    update public.user_stats
       set hearts = v_hearts - v_removed,
           -- regeneration starts counting when the first heart is lost
           hearts_updated_at = case when v_hearts >= c.max_hearts then now() else hearts_updated_at end
     where user_id = p_user;
  end if;
  return v_removed;
end;
$$;

-- Streaks --------------------------------------------------------------------------------

create or replace function private.local_today(p_user uuid)
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone coalesce((select p.timezone from public.profiles p where p.id = p_user), 'UTC'))::date
$$;

-- Streak as it should be displayed today, without mutating anything: a missed day resets it.
create or replace function private.effective_streak(p_current int, p_last_day date, p_today date)
returns int
language sql
immutable
set search_path = ''
as $$
  select case
    when p_last_day is null then 0
    when p_last_day >= p_today - 1 then p_current
    else 0
  end
$$;

-- Registers activity for p_today. Caller must hold the user_stats row lock.
create or replace function private.bump_streak(p_user uuid, p_today date)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  s public.user_stats;
  v_current int;
  v_extended boolean := true;
begin
  select * into s from public.user_stats where user_id = p_user;

  if s.streak_last_day is null then
    v_current := 1;
  elsif s.streak_last_day >= p_today then
    v_current := greatest(s.streak_current, 1);
    v_extended := false;
  elsif s.streak_last_day = p_today - 1 then
    v_current := s.streak_current + 1;
  else
    v_current := 1;
  end if;

  update public.user_stats
     set streak_current = v_current,
         streak_longest = greatest(streak_longest, v_current),
         streak_last_day = greatest(coalesce(streak_last_day, p_today), p_today)
   where user_id = p_user;

  return jsonb_build_object('current', v_current, 'extended_today', v_extended);
end;
$$;

-- Achievements ---------------------------------------------------------------------------

-- Unlocks every achievement whose threshold is now met, credits its gems and returns the ids.
create or replace function private.award_achievements(p_user uuid)
returns text[]
language plpgsql
set search_path = ''
as $$
declare
  v_ids text[];
  v_gems int;
begin
  with metrics as (
    select s.lessons_completed, s.streak_longest, s.level, s.xp,
           (select count(*) from public.trades t where t.user_id = p_user) as trades,
           (select count(*) from public.positions p where p.user_id = p_user) as positions
    from public.user_stats s
    where s.user_id = p_user
  ), unlocked as (
    insert into public.user_achievements (user_id, achievement_id)
    select p_user, a.id
    from public.achievements a, metrics m
    where not exists (
            select 1 from public.user_achievements ua
            where ua.user_id = p_user and ua.achievement_id = a.id)
      and case a.metric
            when 'lessons_completed' then m.lessons_completed
            when 'streak' then m.streak_longest
            when 'level' then m.level
            when 'xp' then m.xp
            when 'trades' then m.trades
            when 'positions' then m.positions
          end >= a.threshold
    on conflict do nothing
    returning achievement_id
  )
  select coalesce(array_agg(u.achievement_id order by a.position), '{}'), coalesce(sum(a.gem_reward), 0)
    into v_ids, v_gems
  from unlocked u
  join public.achievements a on a.id = u.achievement_id;

  if v_gems > 0 then
    update public.user_stats set gems = gems + v_gems where user_id = p_user;
    insert into public.currency_ledger (user_id, currency, amount, reason, ref_id)
    values (p_user, 'gems', v_gems, 'achievements', array_to_string(v_ids, ','));
  end if;

  return v_ids;
end;
$$;
