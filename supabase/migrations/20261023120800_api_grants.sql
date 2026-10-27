-- The complete API surface, in one place.
--
-- Supabase grants every new table/function in `public` to anon and authenticated by
-- default. We revoke everything and grant back only what the clients need; RLS policies
-- then restrict which rows are visible. Later migrations end with their own
-- "API surface" block in the same style (revoke everything, grant back explicitly).

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Read-only reference data
grant select on
  public.tracks, public.track_translations,
  public.units, public.unit_translations,
  public.lessons,
  public.achievements, public.achievement_translations,
  public.instruments, public.quotes_latest, public.quotes_daily, public.fx_rates
to authenticated;

-- The user's own rows (filtered by RLS)
grant select on
  public.profiles, public.consents,
  public.user_stats, public.lesson_attempts, public.lesson_progress,
  public.xp_events, public.currency_ledger, public.user_achievements,
  public.portfolios, public.positions, public.trades, public.portfolio_snapshots
to authenticated;

-- Profile fields the user may edit directly (validated by trigger and check constraints).
grant update (display_name, locale, timezone, display_currency, daily_goal_xp, country_code)
  on public.profiles to authenticated;

grant insert on public.consents to authenticated;

-- RPCs for signed-in users
grant execute on function
  public.get_my_state(),
  public.complete_onboarding(text, text, int, text, text, boolean, boolean),
  public.get_learning_path(text),
  public.start_lesson(text, text),
  public.lose_heart(uuid),
  public.complete_lesson(uuid, jsonb),
  public.refill_hearts(),
  public.buy_streak_freeze(),
  public.place_trade(text, text, uuid, numeric, numeric),
  public.get_portfolio(),
  public.get_weekly_leaderboard(),
  public.get_my_achievements(text),
  public.export_my_data()
to authenticated;
