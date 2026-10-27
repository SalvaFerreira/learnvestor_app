-- Practice mode: short sessions built from exercises the learner got wrong (most recent
-- first), topped up with random exercises from completed lessons. Practice never costs
-- hearts; a good session gives one heart back, so learners who run out can keep learning
-- by reviewing (Duolingo's "practice to earn hearts").

alter table private.game_config
  add column practice_size int not null default 8 check (practice_size between 3 and 20),
  add column practice_xp_per_correct int not null default 2,
  add column practice_heart_min_accuracy numeric not null default 0.8,
  add column max_practice_per_hour int not null default 20;

create table public.practice_sessions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  locale        text not null,
  -- [{ "key": "<lesson>/<exercise>", "lesson_id", "version", "exercise_id" }, ...]
  items         jsonb not null check (jsonb_typeof(items) = 'array'),
  status        text not null default 'started' check (status in ('started', 'completed', 'expired')),
  correct       int,
  total         int,
  xp_awarded    int,
  heart_awarded boolean,
  answers       jsonb,
  started_at    timestamptz not null default now(),
  completed_at  timestamptz
);

create index practice_sessions_user_idx on public.practice_sessions (user_id, started_at desc);

alter table public.practice_sessions enable row level security;
create policy "practice_sessions: read own" on public.practice_sessions
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.start_practice(p_locale text default 'en')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  v_locale text := private.normalize_locale(p_locale);
  v_items jsonb;
  v_session uuid;
begin
  if (select count(*) from public.practice_sessions
      where user_id = v_uid and started_at > now() - interval '1 hour') >= c.max_practice_per_hour then
    raise exception 'rate_limited';
  end if;

  with mistakes as (
    -- latest wrong first-try answer per exercise
    select distinct on (a.lesson_id, k.key) a.lesson_id, k.key as exercise_id, a.started_at
    from public.lesson_attempts a
    join public.lesson_versions v on v.lesson_id = a.lesson_id and v.version = a.version
    cross join lateral jsonb_each(v.answer_key) k
    where a.user_id = v_uid
      and a.status in ('completed', 'failed')
      and a.answers is not null
      and (a.answers -> k.key) is distinct from k.value
    order by a.lesson_id, k.key, a.started_at desc
  ), pool as (
    select l.id as lesson_id, l.published_version as version, k.key as exercise_id, m.started_at as mistake_at
    from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id and l.published_version is not null
    join public.lesson_versions v on v.lesson_id = l.id and v.version = l.published_version
    cross join lateral jsonb_each(v.answer_key) k
    left join mistakes m on m.lesson_id = l.id and m.exercise_id = k.key
    where lp.user_id = v_uid
  ), picked as (
    select * from pool
    order by (mistake_at is null), mistake_at desc, random()
    limit c.practice_size
  )
  select jsonb_agg(jsonb_build_object(
           'key', lesson_id || '/' || exercise_id,
           'lesson_id', lesson_id,
           'version', version,
           'exercise_id', exercise_id))
    into v_items
  from picked;

  if v_items is null then raise exception 'nothing_to_practice'; end if;

  insert into public.practice_sessions (user_id, locale, items)
  values (v_uid, v_locale, v_items)
  returning id into v_session;

  return jsonb_build_object(
    'attempt_id', v_session,
    'lesson_id', null,
    'title', null,
    'hearts', private.hearts_json(v_uid),
    'exercises', (
      select jsonb_agg(
               (select x from jsonb_array_elements(coalesce(t.exercises, te.exercises)) x where x ->> 'id' = it.item ->> 'exercise_id')
               || jsonb_build_object('id', it.item ->> 'key', 'answer', v.answer_key -> (it.item ->> 'exercise_id'))
               order by it.ord)
      from jsonb_array_elements(v_items) with ordinality as it(item, ord)
      join public.lesson_versions v
        on v.lesson_id = it.item ->> 'lesson_id' and v.version = (it.item ->> 'version')::int
      left join public.lesson_translations t
        on t.lesson_id = v.lesson_id and t.version = v.version and t.locale = v_locale
      left join public.lesson_translations te
        on te.lesson_id = v.lesson_id and te.version = v.version and te.locale = 'en'));
end;
$$;

create or replace function public.complete_practice(p_session_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  s public.practice_sessions;
  v_total int;
  v_correct int;
  v_xp int;
  v_xp_today bigint;
  v_today date := private.local_today(v_uid);
  v_hearts int;
  v_heart boolean := false;
  v_level_before int;
  v_level_after int;
  v_streak jsonb;
  v_achievements text[];
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 32768 then
    raise exception 'invalid_answers';
  end if;

  select * into s from public.practice_sessions where id = p_session_id and user_id = v_uid for update;
  if not found then raise exception 'attempt_not_found'; end if;
  if s.status <> 'started' then raise exception 'attempt_closed'; end if;
  if s.started_at < now() - make_interval(mins => c.attempt_ttl_minutes) then
    update public.practice_sessions set status = 'expired', completed_at = now() where id = s.id;
    return jsonb_build_object('status', 'expired');
  end if;

  v_total := jsonb_array_length(s.items);
  if extract(epoch from now() - s.started_at) < v_total * c.min_seconds_per_exercise then
    raise exception 'too_fast';
  end if;

  select count(*) into v_correct
  from jsonb_array_elements(s.items) it(item)
  join public.lesson_versions v
    on v.lesson_id = it.item ->> 'lesson_id' and v.version = (it.item ->> 'version')::int
  where (p_answers -> (it.item ->> 'key')) = (v.answer_key -> (it.item ->> 'exercise_id'));

  perform 1 from public.user_stats where user_id = v_uid for update;
  select level into v_level_before from public.user_stats where user_id = v_uid;

  select coalesce(sum(amount), 0) into v_xp_today
  from public.xp_events where user_id = v_uid and local_date = v_today;
  v_xp := least(v_correct * c.practice_xp_per_correct, greatest(c.daily_xp_cap - v_xp_today, 0))::int;

  if v_xp > 0 then
    insert into public.xp_events (user_id, amount, reason, ref_id, local_date)
    values (v_uid, v_xp, 'practice', s.id::text, v_today);
  end if;

  update public.user_stats
     set xp = xp + v_xp, level = private.level_for_xp(xp + v_xp)
   where user_id = v_uid
  returning level into v_level_after;

  -- A good session earns one heart back.
  if v_total > 0 and v_correct::numeric / v_total >= c.practice_heart_min_accuracy then
    v_hearts := private.sync_hearts(v_uid);
    if v_hearts < c.max_hearts then
      update public.user_stats
         set hearts = v_hearts + 1,
             hearts_updated_at = case when v_hearts + 1 >= c.max_hearts then now() else hearts_updated_at end
       where user_id = v_uid;
      v_heart := true;
    end if;
  end if;

  v_streak := private.bump_streak(v_uid, v_today);

  update public.practice_sessions
     set status = 'completed', completed_at = now(), correct = v_correct, total = v_total,
         xp_awarded = v_xp, heart_awarded = v_heart, answers = p_answers
   where id = s.id;

  v_achievements := private.award_achievements(v_uid);

  return jsonb_build_object(
    'status', 'completed',
    'correct', v_correct,
    'total', v_total,
    'stars', case when v_correct = v_total then 3 when v_correct::numeric / v_total >= 0.75 then 2 else 1 end,
    'first_completion', false,
    'xp_awarded', v_xp,
    'coins_awarded', 0,
    'level', v_level_after,
    'leveled_up', v_level_after > v_level_before,
    'streak', v_streak,
    'heart_awarded', v_heart,
    'hearts', private.hearts_json(v_uid),
    'new_achievements', to_jsonb(v_achievements));
end;
$$;

-- API surface
revoke all on public.practice_sessions from anon, authenticated;
grant select on public.practice_sessions to authenticated;
revoke all on function public.start_practice(text), public.complete_practice(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.start_practice(text), public.complete_practice(uuid, jsonb) to authenticated;
