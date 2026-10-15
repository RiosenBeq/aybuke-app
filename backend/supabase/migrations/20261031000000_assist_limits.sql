-- Limits for Claude's text help (functions/assist) and ai-image's prompt polish.
-- ----------------------------------------------------------------------------
-- Before the server asks Claude anything about her words, it calls
-- admit_assist(p_user, p_ip, p_kind):
--
--   'assist'  POST /assist: prompt ideas, prompt rewrites, caption ideas and
--             makeup picks (free, no credits);
--   'polish'  ai-image, before a Magic Edit or a creation goes to admit_job():
--             Claude classifies the request and writes it as a clear English
--             instruction. Refused here, the job goes on with her own words
--             (admit_job() applies its own limits after it).
--
-- In this order:
--   1. the owner's 'all' pause (private.ai_switches, as admit_job() reads it,
--      the safety breaker's and the provider billing pause included), a block
--      or a running cool-down of the user: 'assist_unavailable' (503). Cloud
--      AI is off for them, so the app falls back to its on-device writer;
--   2. 60 requests an hour per user, then 200 an hour per network address
--      across users, per kind and per UTC hour: 'rate_limited' (429, with
--      retry_after until the hour ends). A refused request still counts.
--
-- Nothing about the text is stored. The counts are kept under salted hashes
-- (private.keyed_hash): of the user id, and of the address, the same key as
-- private.ip_usage. sweep_jobs() deletes them after a day, as it does the
-- per-address job counts; it is otherwise unchanged from 20261022000000.

create table private.assist_usage (
  kind text not null check (kind in ('assist', 'polish')),
  -- keyed_hash('assist_user', user id) or keyed_hash('ip', address).
  bucket text not null,
  hour timestamptz not null,
  requests int not null default 0,
  primary key (kind, bucket, hour)
);
create index assist_usage_hour_idx on private.assist_usage (hour);

alter table private.assist_usage enable row level security;
revoke all on table private.assist_usage from public, anon, authenticated;

create function public.admit_assist(p_user uuid, p_ip text default null, p_kind text default 'assist')
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  c_user_per_hour constant int := 60;
  c_ip_per_hour constant int := 200;
  v_now timestamptz := now();
  v_hour timestamptz := date_trunc('hour', now());
  v_until timestamptz;
  v_count int;
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  if p_kind is null or p_kind not in ('assist', 'polish') then
    raise exception 'unknown kind %', p_kind;
  end if;

  -- 1. Paused, blocked or resting: no cloud AI, so no Claude either.
  select max(s.paused_until) into v_until from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now;
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;
  if private.active_block(p_user, null) then
    return private.error('assist_unavailable', 503);
  end if;
  v_until := private.cooldown_until(p_user, null);
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;

  -- 2. Per user, then per address, for this hour.
  insert into private.assist_usage as u (kind, bucket, hour, requests)
    values (p_kind, private.keyed_hash('assist_user', p_user::text), v_hour, 1)
    on conflict (kind, bucket, hour) do update set requests = u.requests + 1
    returning u.requests into v_count;
  if v_count > c_user_per_hour then
    return private.error('rate_limited', 429, v_hour + interval '1 hour');
  end if;
  if coalesce(p_ip, '') <> '' then
    insert into private.assist_usage as u (kind, bucket, hour, requests)
      values (p_kind, private.keyed_hash('ip', p_ip), v_hour, 1)
      on conflict (kind, bucket, hour) do update set requests = u.requests + 1
      returning u.requests into v_count;
    if v_count > c_ip_per_hour then
      return private.error('rate_limited', 429, v_hour + interval '1 hour');
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- The 20261022000000 cleanup, plus the assist counts after a day.
create or replace function public.sweep_jobs()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  j record;
begin
  select * into pol from public.credit_policy();
  for j in
    update public.jobs
       set status = 'failed', error_code = 'timeout', error_message = 'The job timed out.', updated_at = now()
     where status in ('queued', 'processing') and created_at < now() - interval '15 minutes'
    returning id, retry_of
  loop
    perform public.release_credits(j.id);
    if j.retry_of is not null then
      update public.jobs set retried = false where id = j.retry_of;
    end if;
  end loop;

  for j in
    select id
      from public.jobs
     where status = 'completed' and outputs is not null and updated_at < now() - interval '1 hour'
     order by updated_at
       for update skip locked
  loop
    perform public.settle_unconfirmed(j.id);
  end loop;

  update public.jobs set outputs = null
   where outputs is not null and status <> 'completed' and updated_at < now() - interval '1 hour';
  delete from public.jobs where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '12 months';

  delete from private.blocks
   where (lifted_at is not null and lifted_at < now() - interval '30 days')
      or created_at < now() - interval '12 months';
  delete from private.app_installs i
   where i.last_seen_at < now() - make_interval(days => pol.install_retention_days)
     and not exists (select 1 from private.blocks b where b.install_key = i.key and b.lifted_at is null);
  delete from private.strikes
   where created_at < now() - make_interval(days => pol.cooldown_window_days)
      or (user_id is null and install_key is null);
  delete from private.cooldowns
   where coalesce(lifted_at, ends_at) < now() - make_interval(days => pol.cooldown_window_days)
      or (user_id is null and install_key is null);
  delete from private.ip_usage where hour < now() - interval '1 day';
  delete from private.assist_usage where hour < now() - interval '1 day';
  delete from private.ai_usage_daily where day < (now() at time zone 'utc')::date - 90;
  delete from private.ai_switches where paused_until < now() - interval '1 day';
end $$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.admit_assist(uuid, text, text)',
    'public.sweep_jobs()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
