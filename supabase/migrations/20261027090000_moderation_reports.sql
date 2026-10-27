-- Moderation and content quality.
--   * Usernames are public (weekly leaderboard): they are checked against a blocklist and
--     can be reported by other learners; 3 distinct reports hide the name until reviewed.
--   * Learners can flag a mistake in an exercise (content_reports).
--   * private.exercise_quality / private.lesson_funnel / private.open_content_reports give
--     the content team error rates and drop-off (SQL editor / service role only).

-- Usernames -------------------------------------------------------------------------------

create table private.blocked_terms (
  term text primary key check (term = lower(term) and length(term) >= 3)
);

-- Starter list (PT/EN profanity + names that could impersonate the team). Extend with
-- INSERT statements; matching ignores case, underscores and common digit substitutions.
insert into private.blocked_terms (term) values
  ('admin'), ('administrator'), ('learnvestor'), ('support'), ('suporte'), ('moderator'),
  ('moderador'), ('official'), ('oficial'), ('staff'), ('root'), ('system'), ('sistema'),
  ('fuck'), ('shit'), ('bitch'), ('cunt'), ('whore'), ('slut'), ('nazi'), ('hitler'),
  ('rape'), ('porn'), ('nigger'), ('nigga'), ('faggot'),
  ('caralho'), ('foda'), ('fodase'), ('puta'), ('merda'), ('cona'), ('piça'),
  ('paneleiro'), ('cabrao'), ('cabrão'), ('fdp'), ('crl'), ('broche'), ('punheta'), ('viado');

-- Lower-cases and undoes common "leet" substitutions so f0d4 or p_u_t_a are caught.
create or replace function private.normalize_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$ select translate(replace(lower(coalesce(p_name, '')), '_', ''), '013457@$', 'oieastas') $$;

create or replace function private.is_username_allowed(p_username text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select 1 from private.blocked_terms b
    where position(b.term in private.normalize_name(p_username)) > 0
  )
$$;

alter table public.profiles add column username_flagged boolean not null default false;

create table public.username_reports (
  id               bigint generated always as identity primary key,
  reported_user_id uuid not null references auth.users (id) on delete cascade,
  reporter_id      uuid not null references auth.users (id) on delete cascade,
  created_at       timestamptz not null default now(),
  unique (reported_user_id, reporter_id)
);

alter table public.username_reports enable row level security;
-- No policies: written only through report_username(), read by moderators (service role).

-- Same as the previous version plus the blocklist check.
create or replace function public.complete_onboarding(
  p_username text,
  p_age_bracket text,
  p_daily_goal_xp int,
  p_country_code text,
  p_terms_version text,
  p_marketing_opt_in boolean default false,
  p_analytics_opt_in boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  if p_age_bracket is null or p_age_bracket not in ('16-17', '18-24', '25-34', '35-44', '45-54', '55+') then
    raise exception 'invalid_age_bracket';
  end if;
  if p_terms_version is null or length(p_terms_version) = 0 then
    raise exception 'terms_not_accepted';
  end if;
  if not private.is_username_allowed(p_username) then
    raise exception 'username_not_allowed';
  end if;

  begin
    update public.profiles
       set username = p_username,
           age_bracket = p_age_bracket,
           daily_goal_xp = p_daily_goal_xp,
           country_code = upper(nullif(p_country_code, '')),
           onboarded_at = coalesce(onboarded_at, now())
     where id = v_uid;
  exception
    when unique_violation then raise exception 'username_taken';
    when check_violation then raise exception 'invalid_profile';
  end;

  insert into public.consents (user_id, kind, version, granted) values
    (v_uid, 'terms', p_terms_version, true),
    (v_uid, 'privacy', p_terms_version, true),
    (v_uid, 'marketing', p_terms_version, coalesce(p_marketing_opt_in, false)),
    (v_uid, 'analytics', p_terms_version, coalesce(p_analytics_opt_in, false));

  return public.get_my_state();
end;
$$;

-- Reports a name seen on the leaderboard. Idempotent per reporter.
create or replace function public.report_username(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_target uuid;
begin
  select id into v_target from public.profiles where lower(username) = lower(p_username);
  if v_target is null or v_target = v_uid then return; end if;

  insert into public.username_reports (reported_user_id, reporter_id)
  values (v_target, v_uid)
  on conflict do nothing;

  if (select count(*) from public.username_reports where reported_user_id = v_target) >= 3 then
    update public.profiles set username_flagged = true where id = v_target;
  end if;
end;
$$;

-- Leaderboard: flagged names are replaced by a neutral alias until a moderator reviews them.
create or replace function public.get_weekly_leaderboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_start timestamptz := date_trunc('week', now());
  v_result jsonb;
begin
  with totals as (
    select x.user_id, sum(x.amount)::bigint as xp
    from public.xp_events x
    join public.profiles p on p.id = x.user_id and p.username is not null
    where x.created_at >= v_start
    group by x.user_id
  ), ranked as (
    select t.user_id, t.xp, rank() over (order by t.xp desc) as rnk from totals t
  )
  select jsonb_build_object(
           'week_start', v_start,
           'entries', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'rank', r.rnk,
                      'username', case when p.username_flagged and r.user_id <> v_uid
                                       then 'learner_' || left(replace(r.user_id::text, '-', ''), 6)
                                       else p.username end,
                      'xp', r.xp,
                      'is_me', r.user_id = v_uid)
                    order by r.rnk, p.username)
             from (select * from ranked order by rnk limit 50) r
             join public.profiles p on p.id = r.user_id), '[]'::jsonb),
           'me', (select jsonb_build_object('rank', r.rnk, 'xp', r.xp) from ranked r where r.user_id = v_uid))
    into v_result;
  return v_result;
end;
$$;

-- Content reports ------------------------------------------------------------------------

create table public.content_reports (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users (id) on delete set null,
  lesson_id   text not null references public.lessons (id) on delete cascade,
  version     int not null,
  exercise_id text not null,
  reason      text not null check (reason in ('wrong_answer', 'typo', 'unclear', 'other')),
  message     text check (char_length(message) <= 500),
  status      text not null default 'open' check (status in ('open', 'accepted', 'rejected')),
  created_at  timestamptz not null default now()
);

create index content_reports_open_idx on public.content_reports (lesson_id, version) where status = 'open';

alter table public.content_reports enable row level security;
create policy "content_reports: read own" on public.content_reports
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.report_content(
  p_lesson_id text,
  p_exercise_id text,
  p_reason text,
  p_message text default null,
  p_version int default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_version int := coalesce(p_version, (select published_version from public.lessons where id = p_lesson_id));
begin
  if v_version is null then raise exception 'lesson_not_found'; end if;
  if p_reason is null or p_reason not in ('wrong_answer', 'typo', 'unclear', 'other') then
    raise exception 'invalid_reason';
  end if;
  if (select count(*) from public.content_reports
      where user_id = v_uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'rate_limited';
  end if;
  insert into public.content_reports (user_id, lesson_id, version, exercise_id, reason, message)
  values (v_uid, p_lesson_id, v_version, left(p_exercise_id, 80), p_reason, left(nullif(trim(p_message), ''), 500));
end;
$$;

-- Content quality views (private: SQL editor / service role) -------------------------------

-- First-try error rate per exercise, from the answers stored with each attempt.
create or replace view private.exercise_quality as
select a.lesson_id,
       a.version,
       k.key as exercise_id,
       count(*) as answered,
       round(avg(case when (a.answers -> k.key) = k.value then 0 else 1 end)::numeric, 3) as error_rate
from public.lesson_attempts a
join public.lesson_versions v on v.lesson_id = a.lesson_id and v.version = a.version
cross join lateral jsonb_each(v.answer_key) k
where a.status in ('completed', 'failed') and a.answers is not null
group by a.lesson_id, a.version, k.key;

-- Starts vs completions per lesson version (drop-off).
create or replace view private.lesson_funnel as
select lesson_id,
       version,
       count(*) as started,
       count(*) filter (where status = 'completed') as completed,
       count(*) filter (where status = 'failed') as failed,
       round(count(*) filter (where status = 'completed')::numeric / nullif(count(*), 0), 3) as completion_rate,
       round(avg(extract(epoch from completed_at - started_at)) filter (where status = 'completed')) as avg_seconds
from public.lesson_attempts
group by lesson_id, version;

create or replace view private.open_content_reports as
select lesson_id, version, exercise_id, reason, count(*) as reports, max(created_at) as last_report,
       array_agg(message) filter (where message is not null) as messages
from public.content_reports
where status = 'open'
group by lesson_id, version, exercise_id, reason
order by reports desc;

-- API surface for this migration (see *_api_grants.sql for the conventions).
revoke all on public.username_reports, public.content_reports from anon, authenticated;
grant select on public.content_reports to authenticated;
revoke all on function public.report_username(text), public.report_content(text, text, text, text, int)
  from public, anon, authenticated;
revoke all on function public.complete_onboarding(text, text, int, text, text, boolean, boolean),
  public.get_weekly_leaderboard() from public, anon;
grant execute on function
  public.report_username(text),
  public.report_content(text, text, text, text, int),
  public.complete_onboarding(text, text, int, text, text, boolean, boolean),
  public.get_weekly_leaderboard()
to authenticated;
