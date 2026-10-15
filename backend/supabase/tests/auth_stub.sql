-- Minimal stand-in for Supabase's auth schema and roles, so the migration and
-- tests run on a plain PostgreSQL (CI / local). Never apply this to Supabase.
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz,
  is_anonymous boolean not null default false
);
create table if not exists auth.identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null
);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
grant usage on schema public, auth to anon, authenticated, service_role;
