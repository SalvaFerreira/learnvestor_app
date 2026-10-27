-- Scheduled jobs (pg_cron + pg_net, available on Supabase).
--
-- The market data job calls the market-data-sync Edge Function. It reads two Vault secrets
-- that must be created once per environment (see App/README.md):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<random string, same as CRON_SECRET of the function>', 'cron_secret');
--
-- Guarded so the migration also applies on Postgres instances without these extensions
-- (e.g. the PGlite test harness).

do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron not available: skipping job scheduling';
    return;
  end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  -- Daily point of every portfolio chart.
  perform cron.schedule('portfolio-snapshots', '15 0 * * *', 'select private.snapshot_portfolios()');

  -- Quotes every 5 minutes on weekdays (the function refreshes the oldest quotes first and
  -- fetches the ECB FX rates until today's are available).
  perform cron.schedule('market-data-sync', '*/5 * * * 1-5', $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/market-data-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
      body := '{}'::jsonb,
      timeout_milliseconds := 55000)
  $job$);

  -- Attempts are kept for analytics, but stale "started" ones are closed.
  perform cron.schedule('expire-lesson-attempts', '30 * * * *', $job$
    update public.lesson_attempts
       set status = 'expired', completed_at = now()
     where status = 'started'
       and started_at < now() - make_interval(mins => (select attempt_ttl_minutes from private.game_config))
  $job$);
end;
$$;
