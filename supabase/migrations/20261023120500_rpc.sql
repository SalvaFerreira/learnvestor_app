-- API functions (RPCs). This is the only way clients change game state.
-- Errors are raised with a stable snake_case message that clients map to UI copy.

-- Signup ----------------------------------------------------------------------------------

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c private.game_config := private.config();
  v_locale text := coalesce(new.raw_user_meta_data ->> 'locale', 'en');
  v_tz text := coalesce(new.raw_user_meta_data ->> 'timezone', 'UTC');
  v_portfolio uuid;
begin
  if v_locale not in ('en', 'pt') then v_locale := 'en'; end if;
  if not private.is_valid_timezone(v_tz) then v_tz := 'UTC'; end if;

  insert into public.profiles (id, locale, timezone) values (new.id, v_locale, v_tz);
  insert into public.user_stats (user_id, hearts) values (new.id, c.max_hearts);
  insert into public.portfolios (user_id, cash) values (new.id, c.starting_cash) returning id into v_portfolio;
  insert into public.currency_ledger (user_id, currency, amount, reason)
  values (new.id, 'coins', c.starting_cash, 'welcome_bonus');
  insert into public.portfolio_snapshots (portfolio_id, user_id, day, cash, value)
  values (v_portfolio, new.id, current_date, c.starting_cash, c.starting_cash);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Helpers ---------------------------------------------------------------------------------

create or replace function private.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return v_uid;
end;
$$;

create or replace function private.normalize_locale(p_locale text)
returns text
language sql
immutable
set search_path = ''
as $$ select case when p_locale in ('en', 'pt') then p_locale else 'en' end $$;

create or replace function private.hearts_json(p_user uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  s public.user_stats;
  e record;
begin
  select * into s from public.user_stats where user_id = p_user;
  select * into e from private.effective_hearts(s.hearts, s.hearts_updated_at);
  return jsonb_build_object(
    'hearts', e.hearts,
    'max_hearts', (private.config()).max_hearts,
    'next_heart_at', e.next_heart_at,
    'unlimited', private.has_plus(p_user),
    'gems', s.gems);
end;
$$;

-- State -----------------------------------------------------------------------------------

create or replace function public.get_my_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  p public.profiles;
  s public.user_stats;
  pf public.portfolios;
  e record;
  v_today date := private.local_today(v_uid);
  v_holdings numeric;
  v_xp_today bigint;
begin
  select * into p from public.profiles where id = v_uid;
  select * into s from public.user_stats where user_id = v_uid;
  select * into pf from public.portfolios where user_id = v_uid;
  select * into e from private.effective_hearts(s.hearts, s.hearts_updated_at);
  v_holdings := private.holdings_value(pf.id);
  select coalesce(sum(amount), 0) into v_xp_today
  from public.xp_events where user_id = v_uid and local_date = v_today;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'display_name', p.display_name,
      'locale', p.locale,
      'timezone', p.timezone,
      'country_code', p.country_code,
      'age_bracket', p.age_bracket,
      'daily_goal_xp', p.daily_goal_xp,
      'display_currency', p.display_currency,
      'onboarded', p.onboarded_at is not null),
    'stats', jsonb_build_object(
      'xp', s.xp,
      'level', s.level,
      'level_xp_start', private.xp_for_level(s.level),
      'level_xp_next', private.xp_for_level(s.level + 1),
      'gems', s.gems,
      'hearts', e.hearts,
      'max_hearts', c.max_hearts,
      'next_heart_at', e.next_heart_at,
      'streak', private.effective_streak(s.streak_current, s.streak_last_day, s.streak_freezes, v_today),
      'streak_longest', s.streak_longest,
      'streak_extended_today', coalesce(s.streak_last_day = v_today, false),
      'streak_freezes', s.streak_freezes,
      'lessons_completed', s.lessons_completed,
      'coins_earned', s.coins_earned,
      'xp_today', v_xp_today),
    'portfolio', jsonb_build_object(
      'cash', pf.cash,
      'holdings_value', v_holdings,
      'total_value', pf.cash + v_holdings),
    'is_plus', private.has_plus(v_uid),
    'economy', jsonb_build_object(
      'refill_hearts_gem_cost', c.refill_hearts_gem_cost,
      'streak_freeze_gem_cost', c.streak_freeze_gem_cost,
      'max_streak_freezes', c.max_streak_freezes,
      'min_trade_eur', c.min_trade_eur));
end;
$$;

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

-- Learning path ---------------------------------------------------------------------------

create or replace function public.get_learning_path(p_locale text default 'en')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_locale text := private.normalize_locale(p_locale);
  v_country text;
  v_plus boolean := private.has_plus(v_uid);
  v_result jsonb;
begin
  select country_code into v_country from public.profiles where id = v_uid;

  with visible as (
    select l.*, u.track_id, u.position as unit_position, t.is_premium as track_premium
    from public.lessons l
    join public.units u on u.id = l.unit_id
    join public.tracks t on t.id = u.track_id
    where l.published_version is not null
      and (l.regions is null or v_country = any (l.regions))
  ), ordered as (
    select v.*, lag(v.id) over (partition by v.track_id order by v.unit_position, v.position) as prev_id
    from visible v
  ), lesson_rows as (
    select o.id, o.unit_id, o.track_id, o.position, o.xp_reward, o.coin_reward,
           (o.is_premium or o.track_premium) as premium,
           lp.best_stars,
           lp.lesson_id is not null as completed,
           (o.prev_id is null or exists (
              select 1 from public.lesson_progress pp
              where pp.user_id = v_uid and pp.lesson_id = o.prev_id)) as prev_done,
           coalesce(lt.title, lte.title) as title,
           coalesce(lt.description, lte.description) as description
    from ordered o
    left join public.lesson_progress lp on lp.user_id = v_uid and lp.lesson_id = o.id
    left join public.lesson_translations lt
           on lt.lesson_id = o.id and lt.version = o.published_version and lt.locale = v_locale
    left join public.lesson_translations lte
           on lte.lesson_id = o.id and lte.version = o.published_version and lte.locale = 'en'
  )
  select coalesce(jsonb_agg(x.track_json order by x.track_position), '[]'::jsonb)
    into v_result
  from (
    select t.position as track_position,
           jsonb_build_object(
             'id', t.id,
             'icon', t.icon,
             'color', t.color,
             'is_premium', t.is_premium,
             'title', coalesce(tt.title, tte.title),
             'description', coalesce(tt.description, tte.description),
             'stars_earned', (select coalesce(sum(lr.best_stars), 0) from lesson_rows lr where lr.track_id = t.id),
             'stars_total', (select count(*) * 3 from lesson_rows lr where lr.track_id = t.id),
             'units', (
               select coalesce(jsonb_agg(jsonb_build_object(
                        'id', u.id,
                        'title', coalesce(ut.title, ute.title),
                        'description', coalesce(ut.description, ute.description),
                        'lessons', (
                          select coalesce(jsonb_agg(jsonb_build_object(
                                   'id', lr.id,
                                   'title', lr.title,
                                   'description', lr.description,
                                   'xp_reward', lr.xp_reward,
                                   'coin_reward', lr.coin_reward,
                                   'is_premium', lr.premium,
                                   'stars', lr.best_stars,
                                   'status', case
                                               when lr.completed then 'completed'
                                               when lr.premium and not v_plus then 'premium'
                                               when lr.prev_done then 'unlocked'
                                               else 'locked'
                                             end)
                                 order by lr.position), '[]'::jsonb)
                          from lesson_rows lr where lr.unit_id = u.id))
                      order by u.position), '[]'::jsonb)
               from public.units u
               left join public.unit_translations ut on ut.unit_id = u.id and ut.locale = v_locale
               left join public.unit_translations ute on ute.unit_id = u.id and ute.locale = 'en'
               where u.track_id = t.id
                 and exists (select 1 from lesson_rows lr where lr.unit_id = u.id))
           ) as track_json
    from public.tracks t
    left join public.track_translations tt on tt.track_id = t.id and tt.locale = v_locale
    left join public.track_translations tte on tte.track_id = t.id and tte.locale = 'en'
    where exists (select 1 from lesson_rows lr where lr.track_id = t.id)
  ) x;

  return v_result;
end;
$$;

-- Lessons ---------------------------------------------------------------------------------

create or replace function public.start_lesson(p_lesson_id text, p_locale text default 'en')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  v_locale text := private.normalize_locale(p_locale);
  l public.lessons;
  t public.tracks;
  tr public.lesson_translations;
  v_country text;
  v_plus boolean := private.has_plus(v_uid);
  v_prev text;
  v_recent int;
  v_hearts int;
  v_key jsonb;
  v_attempt uuid;
begin
  select * into l from public.lessons where id = p_lesson_id;
  if not found or l.published_version is null then
    raise exception 'lesson_not_found';
  end if;
  select tk.* into t from public.tracks tk join public.units u on u.track_id = tk.id where u.id = l.unit_id;
  select country_code into v_country from public.profiles where id = v_uid;

  if l.regions is not null and (v_country is null or not v_country = any (l.regions)) then
    raise exception 'lesson_not_found';
  end if;
  if (l.is_premium or t.is_premium) and not v_plus then
    raise exception 'premium_required';
  end if;

  -- Unlock order: the previous lesson of the same track must be completed (replays are fine).
  select s.prev_id into v_prev
  from (
    select l2.id, lag(l2.id) over (order by u2.position, l2.position) as prev_id
    from public.lessons l2
    join public.units u2 on u2.id = l2.unit_id
    where u2.track_id = t.id
      and l2.published_version is not null
      and (l2.regions is null or v_country = any (l2.regions))
  ) s
  where s.id = l.id;

  if v_prev is not null
     and not exists (select 1 from public.lesson_progress where user_id = v_uid and lesson_id = v_prev)
     and not exists (select 1 from public.lesson_progress where user_id = v_uid and lesson_id = l.id) then
    raise exception 'lesson_locked';
  end if;

  select count(*) into v_recent
  from public.lesson_attempts
  where user_id = v_uid and started_at > now() - interval '1 hour';
  if v_recent >= c.max_attempts_per_hour then
    raise exception 'rate_limited';
  end if;

  perform 1 from public.user_stats where user_id = v_uid for update;
  v_hearts := private.sync_hearts(v_uid);
  if not v_plus and v_hearts <= 0 then
    raise exception 'out_of_hearts';
  end if;

  select * into tr from public.lesson_translations
  where lesson_id = l.id and version = l.published_version and locale = v_locale;
  if not found then
    select * into tr from public.lesson_translations
    where lesson_id = l.id and version = l.published_version and locale = 'en';
  end if;
  select answer_key into v_key from public.lesson_versions
  where lesson_id = l.id and version = l.published_version;

  insert into public.lesson_attempts (user_id, lesson_id, version, locale)
  values (v_uid, l.id, l.published_version, tr.locale)
  returning id into v_attempt;

  return jsonb_build_object(
    'attempt_id', v_attempt,
    'lesson_id', l.id,
    'title', tr.title,
    'description', tr.description,
    'xp_reward', l.xp_reward,
    'coin_reward', l.coin_reward,
    'hearts', private.hearts_json(v_uid),
    -- Expected answers are included for instant feedback; the score is still recomputed
    -- server-side in complete_lesson and rewards are protected by the rules there.
    'exercises', (
      select jsonb_agg(
               case when v_key ? (x.e ->> 'id') then x.e || jsonb_build_object('answer', v_key -> (x.e ->> 'id'))
                    else x.e end
               order by x.ord)
      from jsonb_array_elements(tr.exercises) with ordinality as x(e, ord)));
end;
$$;

create or replace function public.lose_heart(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  a public.lesson_attempts;
begin
  select * into a from public.lesson_attempts where id = p_attempt_id and user_id = v_uid for update;
  if not found then raise exception 'attempt_not_found'; end if;
  if a.status <> 'started' then raise exception 'attempt_closed'; end if;

  if not private.has_plus(v_uid) then
    perform 1 from public.user_stats where user_id = v_uid for update;
    if private.deduct_hearts(v_uid, 1) > 0 then
      update public.lesson_attempts set hearts_lost = hearts_lost + 1 where id = a.id;
    end if;
  end if;

  return private.hearts_json(v_uid);
end;
$$;

create or replace function public.complete_lesson(p_attempt_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  a public.lesson_attempts;
  l public.lessons;
  v_key jsonb;
  v_total int;
  v_correct int := 0;
  v_mistakes int;
  v_k text;
  v_plus boolean := private.has_plus(v_uid);
  v_hearts int;
  v_to_deduct int;
  v_first boolean;
  v_stars int;
  v_xp int;
  v_coins numeric;
  v_xp_today bigint;
  v_today date := private.local_today(v_uid);
  v_level_before int;
  v_level_after int;
  v_streak jsonb;
  v_achievements text[];
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 32768 then
    raise exception 'invalid_answers';
  end if;

  select * into a from public.lesson_attempts where id = p_attempt_id and user_id = v_uid for update;
  if not found then raise exception 'attempt_not_found'; end if;
  if a.status <> 'started' then raise exception 'attempt_closed'; end if;

  if a.started_at < now() - make_interval(mins => c.attempt_ttl_minutes) then
    update public.lesson_attempts set status = 'expired', completed_at = now() where id = a.id;
    return jsonb_build_object('status', 'expired');
  end if;

  select answer_key, gradable_count into v_key, v_total
  from public.lesson_versions where lesson_id = a.lesson_id and version = a.version;

  -- Server clock, not client-reported duration.
  if extract(epoch from now() - a.started_at) < v_total * c.min_seconds_per_exercise then
    raise exception 'too_fast';
  end if;

  -- First-try answers are graded against the server's answer key; missing answers count as mistakes.
  for v_k in select jsonb_object_keys(v_key) loop
    if (p_answers -> v_k) = (v_key -> v_k) then
      v_correct := v_correct + 1;
    end if;
  end loop;
  v_mistakes := v_total - v_correct;

  perform 1 from public.user_stats where user_id = v_uid for update;

  -- Hearts not yet taken by lose_heart() are reconciled here, so skipping those calls does not help.
  if not v_plus then
    v_hearts := private.sync_hearts(v_uid);
    v_to_deduct := greatest(v_mistakes - a.hearts_lost, 0);
    if v_to_deduct > v_hearts then
      perform private.deduct_hearts(v_uid, v_hearts);
      update public.lesson_attempts
         set status = 'failed', completed_at = now(), correct = v_correct, mistakes = v_mistakes, answers = p_answers
       where id = a.id;
      return jsonb_build_object('status', 'failed', 'reason', 'out_of_hearts', 'hearts', private.hearts_json(v_uid));
    end if;
    perform private.deduct_hearts(v_uid, v_to_deduct);
  end if;

  select * into l from public.lessons where id = a.lesson_id;
  v_first := not exists (select 1 from public.lesson_progress where user_id = v_uid and lesson_id = l.id);
  v_stars := case
               when v_mistakes = 0 then 3
               when v_correct::numeric / v_total >= 0.75 then 2
               else 1
             end;

  -- Full rewards only the first time; replays give reduced XP and no virtual money
  -- (otherwise lessons could be farmed for portfolio cash).
  v_xp := case
            when v_first then l.xp_reward + case when v_mistakes = 0 then c.perfect_lesson_bonus_xp else 0 end
            else greatest(1, l.xp_reward / c.replay_xp_divisor)
          end;
  v_coins := case when v_first then l.coin_reward else 0 end;

  select coalesce(sum(amount), 0) into v_xp_today
  from public.xp_events where user_id = v_uid and local_date = v_today;
  v_xp := least(v_xp, greatest(c.daily_xp_cap - v_xp_today, 0))::int;

  select level into v_level_before from public.user_stats where user_id = v_uid;

  if v_xp > 0 then
    insert into public.xp_events (user_id, amount, reason, ref_id, local_date)
    values (v_uid, v_xp, 'lesson', a.id::text, v_today);
  end if;

  update public.user_stats
     set xp = xp + v_xp,
         level = private.level_for_xp(xp + v_xp),
         lessons_completed = lessons_completed + case when v_first then 1 else 0 end,
         coins_earned = coins_earned + v_coins
   where user_id = v_uid
  returning level into v_level_after;

  if v_coins > 0 then
    update public.portfolios set cash = cash + v_coins where user_id = v_uid;
    insert into public.currency_ledger (user_id, currency, amount, reason, ref_id)
    values (v_uid, 'coins', v_coins, 'lesson_reward', a.id::text);
  end if;

  insert into public.lesson_progress as lp (user_id, lesson_id, best_stars)
  values (v_uid, l.id, v_stars)
  on conflict (user_id, lesson_id) do update
    set best_stars = greatest(lp.best_stars, excluded.best_stars),
        times_completed = lp.times_completed + 1,
        last_completed_at = now();

  v_streak := private.bump_streak(v_uid, v_today);

  update public.lesson_attempts
     set status = 'completed', completed_at = now(), correct = v_correct, mistakes = v_mistakes,
         stars = v_stars, xp_awarded = v_xp, coins_awarded = v_coins, answers = p_answers
   where id = a.id;

  v_achievements := private.award_achievements(v_uid);

  return jsonb_build_object(
    'status', 'completed',
    'correct', v_correct,
    'total', v_total,
    'stars', v_stars,
    'first_completion', v_first,
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'level', v_level_after,
    'leveled_up', v_level_after > v_level_before,
    'streak', v_streak,
    'hearts', private.hearts_json(v_uid),
    'new_achievements', to_jsonb(v_achievements));
end;
$$;

-- Gem sinks -------------------------------------------------------------------------------

create or replace function public.refill_hearts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  s public.user_stats;
begin
  select * into s from public.user_stats where user_id = v_uid for update;
  if private.sync_hearts(v_uid) >= c.max_hearts then raise exception 'hearts_full'; end if;
  if s.gems < c.refill_hearts_gem_cost then raise exception 'insufficient_gems'; end if;

  update public.user_stats
     set gems = gems - c.refill_hearts_gem_cost, hearts = c.max_hearts, hearts_updated_at = now()
   where user_id = v_uid;
  insert into public.currency_ledger (user_id, currency, amount, reason)
  values (v_uid, 'gems', -c.refill_hearts_gem_cost, 'refill_hearts');

  return private.hearts_json(v_uid);
end;
$$;

create or replace function public.buy_streak_freeze()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  s public.user_stats;
begin
  select * into s from public.user_stats where user_id = v_uid for update;
  if s.streak_freezes >= c.max_streak_freezes then raise exception 'max_streak_freezes'; end if;
  if s.gems < c.streak_freeze_gem_cost then raise exception 'insufficient_gems'; end if;

  update public.user_stats
     set gems = gems - c.streak_freeze_gem_cost, streak_freezes = streak_freezes + 1
   where user_id = v_uid
  returning * into s;
  insert into public.currency_ledger (user_id, currency, amount, reason)
  values (v_uid, 'gems', -c.streak_freeze_gem_cost, 'streak_freeze');

  return jsonb_build_object('gems', s.gems, 'streak_freezes', s.streak_freezes);
end;
$$;

-- Virtual trading -------------------------------------------------------------------------

-- Executes at the server's cached price, never a client-supplied one. Either p_quantity
-- (shares, up to 6 decimals) or p_amount_eur (buy/sell "€50 of Apple") must be given.
create or replace function public.place_trade(
  p_symbol text,
  p_side text,
  p_idempotency_key uuid,
  p_quantity numeric default null,
  p_amount_eur numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  c private.game_config := private.config();
  i public.instruments;
  q public.quotes_latest;
  pf public.portfolios;
  pos public.positions;
  t public.trades;
  v_rate numeric;
  v_price_eur numeric;
  v_qty numeric;
  v_amount numeric;
  v_cost_out numeric;
  v_realized numeric;
  v_recent int;
  v_achievements text[];
begin
  if p_side is null or p_side not in ('buy', 'sell') then raise exception 'invalid_side'; end if;
  if p_idempotency_key is null then raise exception 'missing_idempotency_key'; end if;

  -- A retried request returns the original trade instead of executing twice.
  select * into t from public.trades where user_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('trade', to_jsonb(t), 'cash', (select cash from public.portfolios where id = t.portfolio_id), 'replayed', true);
  end if;

  select * into i from public.instruments where symbol = upper(p_symbol) and is_active;
  if not found then raise exception 'unknown_symbol'; end if;
  select * into q from public.quotes_latest where symbol = i.symbol;
  if not found or q.as_of < now() - make_interval(hours => c.quote_max_age_hours) then
    raise exception 'quote_unavailable';
  end if;
  v_rate := private.fx_rate(i.currency);
  if v_rate is null then raise exception 'fx_unavailable'; end if;
  v_price_eur := q.price / v_rate;

  if p_quantity is not null then
    if p_quantity <= 0 or scale(p_quantity) > 6 then raise exception 'invalid_quantity'; end if;
    v_qty := p_quantity;
  elsif p_amount_eur is not null then
    if p_amount_eur <= 0 then raise exception 'invalid_amount'; end if;
    v_qty := trunc(p_amount_eur / v_price_eur, 6);
  else
    raise exception 'invalid_quantity';
  end if;
  if v_qty <= 0 then raise exception 'invalid_quantity'; end if;

  v_amount := round(v_qty * v_price_eur, 2);
  if v_amount < c.min_trade_eur then raise exception 'amount_too_small'; end if;

  select count(*) into v_recent from public.trades where user_id = v_uid and executed_at > now() - interval '1 hour';
  if v_recent >= c.max_trades_per_hour then raise exception 'rate_limited'; end if;

  select * into pf from public.portfolios where user_id = v_uid for update;

  if p_side = 'buy' then
    if pf.cash < v_amount then raise exception 'insufficient_cash'; end if;
    update public.portfolios set cash = cash - v_amount where id = pf.id returning * into pf;
    insert into public.positions as ps (portfolio_id, user_id, symbol, quantity, cost_basis)
    values (pf.id, v_uid, i.symbol, v_qty, v_amount)
    on conflict (portfolio_id, symbol) do update
      set quantity = ps.quantity + excluded.quantity,
          cost_basis = ps.cost_basis + excluded.cost_basis,
          updated_at = now();
  else
    select * into pos from public.positions where portfolio_id = pf.id and symbol = i.symbol for update;
    if not found or pos.quantity < v_qty then raise exception 'insufficient_shares'; end if;
    v_cost_out := pos.cost_basis * v_qty / pos.quantity;
    v_realized := round(v_amount - v_cost_out, 2);
    if pos.quantity = v_qty then
      delete from public.positions where portfolio_id = pf.id and symbol = i.symbol;
    else
      update public.positions
         set quantity = quantity - v_qty, cost_basis = cost_basis - v_cost_out, updated_at = now()
       where portfolio_id = pf.id and symbol = i.symbol;
    end if;
    update public.portfolios set cash = cash + v_amount where id = pf.id returning * into pf;
  end if;

  insert into public.trades (portfolio_id, user_id, symbol, side, quantity, price, currency, fx_rate,
                             amount_eur, realized_pnl, quote_as_of, idempotency_key)
  values (pf.id, v_uid, i.symbol, p_side, v_qty, q.price, i.currency, v_rate,
          v_amount, v_realized, q.as_of, p_idempotency_key)
  returning * into t;

  insert into public.currency_ledger (user_id, currency, amount, reason, ref_id)
  values (v_uid, 'coins', case when p_side = 'buy' then -v_amount else v_amount end, 'trade_' || p_side, t.id::text);

  v_achievements := private.award_achievements(v_uid);

  return jsonb_build_object(
    'trade', to_jsonb(t),
    'cash', pf.cash,
    'replayed', false,
    'new_achievements', to_jsonb(v_achievements));
end;
$$;

create or replace function public.get_portfolio()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  pf public.portfolios;
  v_holdings numeric;
begin
  select * into pf from public.portfolios where user_id = v_uid;
  v_holdings := private.holdings_value(pf.id);

  return jsonb_build_object(
    'cash', pf.cash,
    'holdings_value', v_holdings,
    'total_value', pf.cash + v_holdings,
    'positions', coalesce((
      select jsonb_agg(row_to_json(r)::jsonb order by r.value_eur desc)
      from (
        select p.symbol, i.name, i.logo_url, i.sector, i.currency,
               p.quantity,
               round(p.cost_basis, 2) as cost_basis_eur,
               q.price,
               q.change_pct,
               q.as_of,
               round(q.price / private.fx_rate(i.currency), 6) as price_eur,
               coalesce(round(p.quantity * q.price / private.fx_rate(i.currency), 2), round(p.cost_basis, 2)) as value_eur
        from public.positions p
        join public.instruments i on i.symbol = p.symbol
        left join public.quotes_latest q on q.symbol = p.symbol
        where p.portfolio_id = pf.id
      ) r), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('day', h.day, 'value', h.value) order by h.day)
      from (
        select s.day, s.value from public.portfolio_snapshots s
        where s.portfolio_id = pf.id
        order by s.day desc
        limit 180
      ) h), '[]'::jsonb),
    'recent_trades', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'symbol', t.symbol, 'side', t.side, 'quantity', t.quantity,
               'amount_eur', t.amount_eur, 'realized_pnl', t.realized_pnl, 'executed_at', t.executed_at)
             order by t.executed_at desc)
      from (select * from public.trades where portfolio_id = pf.id order by executed_at desc limit 20) t), '[]'::jsonb));
end;
$$;

-- Social / achievements -------------------------------------------------------------------

-- Weekly XP ranking (UTC weeks). At larger scale this moves to Redis sorted sets with
-- leagues of ~30 learners; the RPC contract can stay the same.
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
                      'rank', r.rnk, 'username', p.username, 'xp', r.xp, 'is_me', r.user_id = v_uid)
                    order by r.rnk, p.username)
             from (select * from ranked order by rnk limit 50) r
             join public.profiles p on p.id = r.user_id), '[]'::jsonb),
           'me', (select jsonb_build_object('rank', r.rnk, 'xp', r.xp) from ranked r where r.user_id = v_uid))
    into v_result;
  return v_result;
end;
$$;

create or replace function public.get_my_achievements(p_locale text default 'en')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_locale text := private.normalize_locale(p_locale);
  s public.user_stats;
  v_trades bigint;
  v_positions bigint;
begin
  select * into s from public.user_stats where user_id = v_uid;
  select count(*) into v_trades from public.trades where user_id = v_uid;
  select count(*) into v_positions from public.positions where user_id = v_uid;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id,
             'icon', a.icon,
             'title', coalesce(t.title, te.title),
             'description', coalesce(t.description, te.description),
             'threshold', a.threshold,
             'gem_reward', a.gem_reward,
             'progress', least(a.threshold, case a.metric
                           when 'lessons_completed' then s.lessons_completed
                           when 'streak' then s.streak_longest
                           when 'level' then s.level
                           when 'xp' then s.xp
                           when 'trades' then v_trades
                           when 'positions' then v_positions
                         end),
             'unlocked_at', ua.unlocked_at)
           order by a.position)
    from public.achievements a
    left join public.achievement_translations t on t.achievement_id = a.id and t.locale = v_locale
    left join public.achievement_translations te on te.achievement_id = a.id and te.locale = 'en'
    left join public.user_achievements ua on ua.achievement_id = a.id and ua.user_id = v_uid), '[]'::jsonb);
end;
$$;

-- GDPR ------------------------------------------------------------------------------------

-- Right of access / portability: everything we store about the caller in one document.
-- (Account deletion is handled by the delete-account Edge Function; all user data
-- cascades from auth.users.)
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = v_uid),
    'consents', (select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at), '[]') from public.consents c where c.user_id = v_uid),
    'stats', (select to_jsonb(s) from public.user_stats s where s.user_id = v_uid),
    'lesson_progress', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.lesson_progress x where x.user_id = v_uid),
    'lesson_attempts', (select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at), '[]') from public.lesson_attempts x where x.user_id = v_uid),
    'xp_events', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from public.xp_events x where x.user_id = v_uid),
    'currency_ledger', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from public.currency_ledger x where x.user_id = v_uid),
    'achievements', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.user_achievements x where x.user_id = v_uid),
    'portfolio', (select to_jsonb(x) from public.portfolios x where x.user_id = v_uid),
    'positions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.positions x where x.user_id = v_uid),
    'trades', (select coalesce(jsonb_agg(to_jsonb(x) order by x.executed_at), '[]') from public.trades x where x.user_id = v_uid),
    'entitlements', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.entitlements x where x.user_id = v_uid),
    'purchases', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.purchases x where x.user_id = v_uid));
end;
$$;

-- Service functions (webhooks, service_role only) ------------------------------------------

create or replace function public.svc_apply_entitlement(
  p_user uuid,
  p_entitlement text,
  p_source text,
  p_product_id text,
  p_is_active boolean,
  p_expires_at timestamptz,
  p_original_transaction_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.entitlements as e
    (user_id, entitlement, source, product_id, is_active, expires_at, original_transaction_id)
  values (p_user, p_entitlement, p_source, p_product_id, p_is_active, p_expires_at, p_original_transaction_id)
  on conflict (user_id, entitlement) do update
    set source = excluded.source,
        product_id = excluded.product_id,
        is_active = excluded.is_active,
        expires_at = excluded.expires_at,
        original_transaction_id = coalesce(excluded.original_transaction_id, e.original_transaction_id);
end;
$$;

-- Returns false when the transaction was already credited (webhook retries).
create or replace function public.svc_credit_gems(
  p_user uuid,
  p_gems int,
  p_source text,
  p_transaction_id text,
  p_product_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_gems <= 0 then raise exception 'invalid_gems'; end if;
  insert into public.purchases (user_id, source, transaction_id, product_id, kind, quantity)
  values (p_user, p_source, p_transaction_id, p_product_id, 'gems', p_gems)
  on conflict (transaction_id) do nothing;
  if not found then return false; end if;

  update public.user_stats set gems = gems + p_gems where user_id = p_user;
  insert into public.currency_ledger (user_id, currency, amount, reason, ref_id)
  values (p_user, 'gems', p_gems, 'purchase', p_transaction_id);
  return true;
end;
$$;
