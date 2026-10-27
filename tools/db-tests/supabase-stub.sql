-- Minimal stand-in for the parts of Supabase our migrations rely on: API roles, the auth
-- schema with auth.users and auth.uid(), and Supabase's default privileges (so the
-- revokes in *_api_grants.sql are exercised exactly as on a real project).

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema auth;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  is_anonymous       boolean not null default false,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);

create function auth.uid() returns uuid
language sql stable
as $$ select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;

-- Demo API only (dev-server.mjs and the web demo): the JWT signing secret and refresh
-- tokens live in the database, so sessions survive a restart of the API or a page reload.
create table auth.demo_secret (
  id     boolean primary key default true check (id),
  secret text not null default gen_random_uuid()::text || gen_random_uuid()::text
);
insert into auth.demo_secret default values;

create table auth.refresh_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
