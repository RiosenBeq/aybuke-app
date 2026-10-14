-- Keep-alive heartbeat.
-- ----------------------------------------------------------------------------
-- Free Supabase projects are paused after about a week without user database
-- activity, which would take every AI feature offline (App Review included).
-- Once a day .github/workflows/keepalive.yml calls keepalive() through the
-- public API with the anon key, which is public by design and already ships in
-- AppConfig.json. The call writes this one row, so it counts as real database
-- activity. Nothing else is exposed: the table is closed to anon and
-- authenticated, and the function only stamps the time.
create table public.ops_heartbeat (
  id smallint primary key default 1 check (id = 1),
  seen_at timestamptz not null default now()
);
alter table public.ops_heartbeat enable row level security;
revoke all on table public.ops_heartbeat from anon, authenticated;
grant all on table public.ops_heartbeat to service_role;

create or replace function public.keepalive()
returns timestamptz
language sql security definer set search_path = public as $$
  insert into public.ops_heartbeat (id, seen_at) values (1, now())
  on conflict (id) do update set seen_at = excluded.seen_at
  returning seen_at;
$$;
revoke execute on function public.keepalive() from public, authenticated;
grant execute on function public.keepalive() to anon, service_role;
