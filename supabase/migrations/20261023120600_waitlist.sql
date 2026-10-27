-- Website waitlist. The landing page calls join_waitlist() with the public anon key;
-- the table itself is not readable through the API.

create table public.waitlist_signups (
  id         bigint generated always as identity primary key,
  email      text not null unique
             check (email = lower(email) and length(email) <= 254 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  locale     text,
  source     text,
  created_at timestamptz not null default now()
);

alter table public.waitlist_signups enable row level security;

-- Always succeeds for a well-formed email (also when already registered), so the endpoint
-- cannot be used to discover who is on the list.
create or replace function public.join_waitlist(p_email text, p_locale text default null, p_source text default 'website')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if v_email is null or length(v_email) > 254 or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    raise exception 'invalid_email';
  end if;
  insert into public.waitlist_signups (email, locale, source)
  values (v_email, left(p_locale, 10), left(p_source, 40))
  on conflict (email) do nothing;
end;
$$;
