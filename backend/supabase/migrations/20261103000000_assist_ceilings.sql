-- Claude's capacity goes to the safety checks first (security review, 16 October 2026).
-- ----------------------------------------------------------------------------
-- Writing help (functions/assist) and the prompt polish (ai-image, off while
-- PROMPT_POLISH=off) ask Claude like the safety checks of photos, results and
-- poll pictures, and by default with the same ANTHROPIC_API_KEY. With only the
-- per-user and per-address limits of 20261031000000, free anonymous users
-- could flood writing help until the Anthropic organization hit its rate or
-- spend limit; the result checks then failed closed, the safety breaker
-- (20261029000001) paused all AI and kept tripping. So:
--
--   1. assist_policy(): the numbers below, in one place.
--   2. admit_assist() takes the App Store install proof that ai-image and
--      polls already verify (X-App-Transaction, _shared/apple.ts):
--        - blocks and cool-downs follow the install too (or, without one, the
--          address, as admit_job() keys them);
--        - a verified install has its own hourly bucket across its accounts,
--          next to the per-user and per-address ones (unchanged);
--        - callers without a verified install share one small hourly cap;
--        - then ceilings for everyone, writing help and the polish together:
--          20 a minute, 200 an hour and 1,000 a UTC day (about $0.30 of
--          Claude Haiku 5.5). Claude Haiku 5.5's Start tier allows 1,000
--          requests a minute, so 20 leave at least 98% of it to the safety
--          checks (and 60% of a 50-a-minute limit);
--        - no writing help or polish while a result check failed in the last
--          5 minutes (the safety breaker's last error) or AI is paused, so
--          Claude's capacity goes to the safety checks first.
--      Over a ceiling, or while the safety check is struggling: 503
--      assist_unavailable with retry_after, as for a pause. The app then uses
--      its on-device writer, and the polish leaves her words as they are.
--      Ceilings count only what they admit; the per-user, per-install and
--      per-address counts still count refused requests (20261031000000).
--      The three-argument form the deployed functions call stays, as a
--      request without install proof.
--   3. job_admissible(): a read-only look at whether admit_job() could take a
--      job right now (not paused, not blocked or resting, under the breakers
--      and rate limits, a credit, a free daily credit or a free retry to pay
--      with), so the polish asks Claude only about jobs that can run.
--
-- The counts are salted hashes or plain totals (private.assist_ceilings has
-- no ids), deleted after a day by sweep_jobs().

-- MARK: Policy

-- The numbers for writing help and the polish. Change them here (a new
-- migration that replaces the function) to retune without an app update.
create function public.assist_policy(
  out user_per_hour int,
  out ip_per_hour int,
  out install_per_hour int,
  out unverified_per_hour int,
  out all_per_minute int,
  out all_per_hour int,
  out all_per_day int,
  out quiet_after_check_error_minutes int
)
language sql immutable
set search_path = ''
as $$
  select
    60,    -- user_per_hour: per account and kind (20261031000000)
    200,   -- ip_per_hour: per network address across accounts, per kind (20261031000000)
    60,    -- install_per_hour: per verified App Store install across its accounts, per kind
    30,    -- unverified_per_hour: everyone without a verified install together, both kinds
    20,    -- all_per_minute: everyone, both kinds (Haiku 5.5's Start tier: 1,000 a minute)
    200,   -- all_per_hour: everyone, both kinds
    1000,  -- all_per_day: everyone, both kinds, per UTC day (about $0.30 of Claude)
    5      -- quiet_after_check_error_minutes: none this long after a result check failed
$$;

-- MARK: Ceilings

create table private.assist_ceilings (
  scope text not null check (scope in ('all_minute', 'all_hour', 'all_day', 'unverified_hour')),
  -- The minute, hour or UTC day the count is for.
  period timestamptz not null,
  requests int not null default 0 check (requests >= 0),
  primary key (scope, period)
);
create index assist_ceilings_period_idx on private.assist_ceilings (period);

alter table private.assist_ceilings enable row level security;
revoke all on table private.assist_ceilings from public, anon, authenticated;

-- Takes one place under a ceiling: true when there was one (it's counted),
-- false when the ceiling is reached (nothing counted). Racing requests queue
-- on the counter's row, so a ceiling is never passed.
create function private.assist_take(p_scope text, p_period timestamptz, p_max int)
returns boolean
language plpgsql volatile
set search_path = ''
as $$
declare
  v_rows int;
begin
  if coalesce(p_max, 0) <= 0 then
    return false;
  end if;
  insert into private.assist_ceilings as c (scope, period, requests)
    values (p_scope, p_period, 1)
    on conflict (scope, period) do update set requests = c.requests + 1 where c.requests < p_max;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end $$;

-- Gives back a place a later ceiling refused.
create function private.assist_give_back(p_scope text, p_period timestamptz)
returns void
language sql volatile
set search_path = ''
as $$
  update private.assist_ceilings set requests = greatest(requests - 1, 0)
   where scope = p_scope and period = p_period
$$;

revoke all on function private.assist_take(text, timestamptz, int) from public, anon, authenticated;
revoke all on function private.assist_give_back(text, timestamptz) from public, anon, authenticated;

-- MARK: Admission

-- Before the server asks Claude anything about her words (p_kind 'assist':
-- POST /assist; 'polish': ai-image before admit_job()). In this order:
--   1. AI paused for everyone ('all' in private.ai_switches: the owner, the
--      provider billing pause, the safety breaker), then a result check that
--      failed within quiet_after_check_error_minutes: 503 assist_unavailable
--      until it ends;
--   2. a block or a running cool-down of the user, or of her verified install
--      (her address without one): 503 assist_unavailable;
--   3. per user, per verified install and per address, per kind and UTC hour:
--      429 rate_limited until the hour ends (a refused request still counts);
--   4. without a verified install, the shared hourly cap; then everyone's
--      ceilings a minute, an hour and a UTC day: 503 assist_unavailable until
--      that period ends. These count only the requests they admit.
-- Nothing is counted in 1 and 2.
create function public.admit_assist(
  p_user uuid,
  p_ip text,
  p_kind text,
  p_app_transaction_id text,
  p_install_status text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_now timestamptz := now();
  v_minute timestamptz := date_trunc('minute', now());
  v_hour timestamptz := date_trunc('hour', now());
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text;
  v_abuse text;
  v_until timestamptz;
  v_count int;
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  if p_kind is null or p_kind not in ('assist', 'polish') then
    raise exception 'unknown kind %', p_kind;
  end if;
  select * into pol from public.assist_policy();
  -- The verified install's key, as touch_install() and admit_poll() make it;
  -- strikes, cool-downs and blocks fall back to the address, as in admit_job().
  v_install := case when p_install_status = 'verified' and coalesce(p_app_transaction_id, '') <> ''
                    then private.keyed_hash('app_transaction', p_app_transaction_id) end;
  v_abuse := coalesce(v_install, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);

  -- 1. Paused, or the safety check is struggling: Claude is for the checks now.
  select max(s.paused_until) into v_until from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now;
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;
  select b.last_error_at + make_interval(mins => pol.quiet_after_check_error_minutes) into v_until
    from private.safety_breaker b;
  if v_until > v_now then
    return private.error('assist_unavailable', 503, v_until);
  end if;

  -- 2. Blocked or resting: no cloud AI, so no Claude either.
  if private.active_block(p_user, v_abuse) then
    return private.error('assist_unavailable', 503);
  end if;
  v_until := private.cooldown_until(p_user, v_abuse);
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;

  -- 3. Per user, per install, then per address, for this hour.
  insert into private.assist_usage as u (kind, bucket, hour, requests)
    values (p_kind, private.keyed_hash('assist_user', p_user::text), v_hour, 1)
    on conflict (kind, bucket, hour) do update set requests = u.requests + 1
    returning u.requests into v_count;
  if v_count > pol.user_per_hour then
    return private.error('rate_limited', 429, v_hour + interval '1 hour');
  end if;
  if v_install is not null then
    insert into private.assist_usage as u (kind, bucket, hour, requests)
      values (p_kind, v_install, v_hour, 1)
      on conflict (kind, bucket, hour) do update set requests = u.requests + 1
      returning u.requests into v_count;
    if v_count > pol.install_per_hour then
      return private.error('rate_limited', 429, v_hour + interval '1 hour');
    end if;
  end if;
  if coalesce(p_ip, '') <> '' then
    insert into private.assist_usage as u (kind, bucket, hour, requests)
      values (p_kind, private.keyed_hash('ip', p_ip), v_hour, 1)
      on conflict (kind, bucket, hour) do update set requests = u.requests + 1
      returning u.requests into v_count;
    if v_count > pol.ip_per_hour then
      return private.error('rate_limited', 429, v_hour + interval '1 hour');
    end if;
  end if;

  -- 4. The ceilings. A place one of them took is given back when a later one refuses.
  if v_install is null and not private.assist_take('unverified_hour', v_hour, pol.unverified_per_hour) then
    return private.error('assist_unavailable', 503, v_hour + interval '1 hour');
  end if;
  if not private.assist_take('all_minute', v_minute, pol.all_per_minute) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    return private.error('assist_unavailable', 503, v_minute + interval '1 minute');
  end if;
  if not private.assist_take('all_hour', v_hour, pol.all_per_hour) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    perform private.assist_give_back('all_minute', v_minute);
    return private.error('assist_unavailable', 503, v_hour + interval '1 hour');
  end if;
  if not private.assist_take('all_day', v_day, pol.all_per_day) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    perform private.assist_give_back('all_minute', v_minute);
    perform private.assist_give_back('all_hour', v_hour);
    return private.error('assist_unavailable', 503, private.next_utc_day());
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- The form the deployed assist and ai-image call (20261031000000): a request
-- without install proof, so it shares the unverified cap.
create or replace function public.admit_assist(p_user uuid, p_ip text default null, p_kind text default 'assist')
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  return public.admit_assist(p_user, p_ip, p_kind, null::text, 'missing'::text);
end $$;

-- MARK: Could admit_job() take it?

-- Read-only (stable: it writes nothing, not even the install), for the prompt
-- polish: {"ok": true} when admit_job() would admit this job right now, else
-- the refusal admit_job() would give (install_blocked, cooldown, ai_paused,
-- rate_limited, usage_limit, retry_unavailable, retry_limit,
-- app_transaction_required/invalid, insufficient_credits). It doesn't look at
-- the prompt: a blocked prompt never gets this far. Racing requests can still
-- change the answer, so admit_job() decides as before.
create function public.job_admissible(
  p_user uuid,
  p_operation text,
  p_outputs int default 1,
  p_retry_of uuid default null,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_ip text default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  pol record;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'utc')::date;
  v_key text;
  v_kind text;
  v_abuse text;
  v_until timestamptz;
  v_usage private.ai_usage_daily;
  v_switch_free boolean;
  v_is_pro boolean;
  v_count int;
  v_oldest timestamptz;
  v_limit int;
  v_original public.jobs;
  e public.entitlements;
  i private.app_installs;
  v_allow_daily boolean;
  v_paused boolean := false;
  v_daily int := 0;
  v_subscription int := 0;
  v_purchased int := 0;
  v_due boolean := false;
  v_cost int := greatest(1, coalesce(p_outputs, 1));
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  select * into pol from public.credit_policy();
  -- The install's key as touch_install() makes it, without recording it.
  if p_install_status = 'verified' then
    if coalesce(p_app_transaction_id, '') <> '' then
      v_key := private.keyed_hash('app_transaction', p_app_transaction_id);
      v_kind := 'app_store';
    else
      v_key := private.keyed_hash('user', p_user::text);
      v_kind := 'unverified';
    end if;
  end if;
  v_abuse := coalesce(v_key, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);

  -- admit_job() 1–3: blocked, resting, paused, the day's hard breaker.
  if private.active_block(p_user, v_abuse) then
    return private.error('install_blocked', 403);
  end if;
  v_until := private.cooldown_until(p_user, v_abuse);
  if v_until is not null then
    return private.error('cooldown', 429, v_until);
  end if;
  select max(s.paused_until) into v_until from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now;
  if v_until is not null then
    return private.error('ai_paused', 503, v_until);
  end if;
  v_switch_free := exists (select 1 from private.ai_switches s where s.scope = 'free' and s.paused_until > v_now);
  select * into v_usage from private.ai_usage_daily where day = v_today;
  if coalesce(v_usage.total_jobs, 0) >= pol.all_jobs_daily_cap then
    return private.error('ai_paused', 503, private.next_utc_day());
  end if;

  -- 4. The rate limits, as admit_job() counts them (the address count as it stands).
  select * into e from public.entitlements
   where user_id = p_user and not revoked and expires_at > v_now
   order by expires_at desc
   limit 1;
  v_is_pro := e.original_transaction_id is not null;
  v_limit := case when v_is_pro then pol.jobs_per_minute_pro else pol.jobs_per_minute_free end;
  select count(*), min(created_at) into v_count, v_oldest from public.jobs
   where user_id = p_user and created_at > v_now - interval '1 minute';
  if v_count >= v_limit then
    return private.error('rate_limited', 429, v_oldest + interval '1 minute');
  end if;
  v_limit := case when v_is_pro then pol.jobs_per_hour_pro else pol.jobs_per_hour_free end;
  select count(*), min(created_at) into v_count, v_oldest from public.jobs
   where user_id = p_user and created_at > v_now - interval '1 hour';
  if v_count >= v_limit then
    return private.error('usage_limit', 429, v_oldest + interval '1 hour');
  end if;
  v_limit := case when v_is_pro then pol.jobs_per_day_pro else pol.jobs_per_day_free end;
  select count(*), min(created_at) into v_count, v_oldest from public.jobs
   where user_id = p_user and created_at > v_now - interval '1 day';
  if v_count >= v_limit then
    return private.error('usage_limit', 429, v_oldest + interval '1 day');
  end if;
  if coalesce(p_ip, '') <> '' and pol.ip_jobs_per_hour > 0 then
    select u.requests into v_count from private.ip_usage u
     where u.ip_key = private.keyed_hash('ip', p_ip) and u.hour = date_trunc('hour', v_now);
    if coalesce(v_count, 0) >= pol.ip_jobs_per_hour then
      return private.error('usage_limit', 429, date_trunc('hour', v_now) + interval '1 hour');
    end if;
  end if;

  -- 6. A free retry costs nothing: its original and today's retries decide.
  if p_retry_of is not null then
    select * into v_original from public.jobs
     where id = p_retry_of and user_id = p_user and operation = p_operation and status = 'completed'
       and not retried and created_at > v_now - interval '15 minutes';
    if not found then
      return private.error('retry_unavailable', 409);
    end if;
    select count(*) into v_count from public.jobs
     where user_id = p_user and retry_of is not null and created_at >= v_today::timestamp at time zone 'utc'
       and status in ('queued', 'processing', 'completed');
    if v_count >= pol.free_retries_daily then
      return private.error('retry_limit', 409, private.next_utc_day());
    end if;
    if v_original.free and (v_switch_free or coalesce(v_usage.free_jobs, 0) >= pol.free_jobs_daily_cap) then
      return private.error('ai_paused', 503, private.next_utc_day());
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- 7. What she can pay with right now (private.balance_of(), with the free
  --    breakers as admit_job() applies them). A subscription that's due its
  --    credits (refresh_subscription() would grant them) counts as paid for.
  if v_is_pro then
    v_subscription := coalesce(e.credits, 0);
    v_due := case when e.is_trial then not e.trial_granted
                  else e.credits_period_start is null or e.credits_trial
                       or e.credits_period_start + interval '1 month' <= v_now end;
  end if;
  select coalesce(w.purchased, 0) into v_purchased from public.credit_wallets w where w.user_id = p_user;
  v_purchased := coalesce(v_purchased, 0);
  v_allow_daily := not v_is_pro and v_key is not null;
  if v_allow_daily and (v_switch_free or coalesce(v_usage.free_jobs, 0) >= pol.free_jobs_daily_cap
      or (v_kind = 'unverified' and coalesce(v_usage.unverified_jobs, 0) >= pol.unverified_jobs_daily_cap)) then
    v_allow_daily := false;
    v_paused := true;
  end if;
  if not v_is_pro and v_key is not null then
    select * into i from private.app_installs where key = v_key;
    -- A new install starts with today's free credits; a new UTC day refills them.
    v_daily := case when i.key is null or i.daily_period < v_today then pol.free_daily else i.daily end;
  end if;
  if v_due or (case when v_allow_daily then v_daily else 0 end) + v_subscription + v_purchased >= v_cost then
    return jsonb_build_object('ok', true);
  end if;
  if v_paused and v_daily + v_subscription + v_purchased >= v_cost then
    return private.error('ai_paused', 503, private.next_utc_day());
  end if;
  if not v_is_pro and v_key is null and v_subscription + v_purchased < v_cost then
    return private.error(case when p_install_status = 'invalid' then 'app_transaction_invalid'
                              else 'app_transaction_required' end, 428);
  end if;
  return jsonb_build_object('ok', false, 'code', 'insufficient_credits', 'status', 402);
end $$;

-- MARK: Housekeeping

-- The 20261102000000 cleanup, plus the ceilings after a day.
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
  delete from private.assist_ceilings where period < now() - interval '1 day';
  delete from private.ai_usage_daily where day < (now() at time zone 'utc')::date - 90;
  delete from private.ai_switches where paused_until < now() - interval '1 day';

  delete from private.polls where expires_at <= now();
  delete from private.poll_reports
   where created_at < now() - make_interval(days => (select p.report_retention_days from public.poll_policy() p));
  delete from private.poll_usage where period < now() - interval '2 days';
  delete from private.poll_daily where day < (now() at time zone 'utc')::date - 90;
end $$;

-- MARK: Privileges

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.assist_policy()',
    'public.admit_assist(uuid, text, text, text, text)',
    'public.admit_assist(uuid, text, text)',
    'public.job_admissible(uuid, text, int, uuid, text, text, text)',
    'public.sweep_jobs()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
