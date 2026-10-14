-- Abuse controls: circuit breakers, rate limits, strikes, cool-downs, blocks
-- and the owner's tools.
-- ----------------------------------------------------------------------------
-- Every cloud job now goes through admit_job(), one transaction that, in
-- this order:
--
--   1. refuses a blocked install or user ('install_blocked');
--   2. refuses during a cool-down ('cooldown');
--   3. turns a prompt the server's policy blocked into a strike, never a
--      charge ('content_blocked', or 'cooldown' when that strike starts one);
--   4. pauses everything when the owner flipped the switch or the day's hard
--      breaker (all_jobs_daily_cap) is reached ('ai_paused');
--   5. applies the per-user limits per minute ('rate_limited') and per hour
--      and day ('usage_limit'), and the per-IP limit across users;
--   6. checks a Likeness Lock retry (one per result, free_retries_daily a day);
--   7. pays: free daily credits from the App Store install unless the free
--      breaker (free_jobs_daily_cap, or unverified_jobs_daily_cap for installs
--      without an appTransactionId) is reached, then the subscription, then
--      packs. Short of credits, it says why: 'ai_paused' (only the free part
--      is paused), 'app_transaction_required'/'app_transaction_invalid' (no
--      verified install, so no free credits) or 'insufficient_credits';
--   8. books the job, the hold and the day's counters.
--
-- Nothing is charged unless the job is admitted. Paid users keep working when
-- only the free breaker trips. All numbers are in credit_policy().
--
-- Strikes are server-side safety blocks: a prompt the policy blocks, or an
-- output the moderation flags (flag_job()). They are counted per user and
-- per install key. strikes_for_cooldown within strike_window_hours start a
-- cool-down (no cloud AI for cooldown_hours, no paywall); cooldowns_for_block
-- cool-downs within cooldown_window_days block the install (or the user,
-- without one) until the owner lifts it with ops_unblock().
--
-- Retention (sweep_jobs()): hashed installs install_retention_days after
-- their last use, unless blocked; strikes and cool-downs after
-- cooldown_window_days; per-IP counters after a day; lifted blocks after 30
-- days and every block after 12 months; daily counters after 90 days. The
-- install and IP data are salted hashes with counts, and survive "Delete my
-- data" (only the link to the deleted user goes), solely to prevent abuse.
--
-- All of it lives in the `private` schema: no API role can read it.

-- MARK: Tables

create table private.ai_usage_daily (
  day date primary key,
  total_jobs int not null default 0,
  free_jobs int not null default 0,
  unverified_jobs int not null default 0,
  est_cost_cents bigint not null default 0
);

create table private.ip_usage (
  ip_key text not null,
  hour timestamptz not null,
  requests int not null default 0,
  primary key (ip_key, hour)
);

create table private.strikes (
  id bigserial primary key,
  user_id uuid references auth.users (id) on delete set null,
  install_key text,
  source text not null check (source in ('prompt', 'output')),
  category text,
  job_id uuid,
  created_at timestamptz not null default now()
);
create index strikes_user_idx on private.strikes (user_id, created_at desc) where user_id is not null;
create index strikes_install_idx on private.strikes (install_key, created_at desc) where install_key is not null;
create index strikes_created_idx on private.strikes (created_at);

create table private.cooldowns (
  id bigserial primary key,
  user_id uuid references auth.users (id) on delete set null,
  install_key text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  lifted_at timestamptz
);
create index cooldowns_user_idx on private.cooldowns (user_id, ends_at desc) where user_id is not null;
create index cooldowns_install_idx on private.cooldowns (install_key, ends_at desc) where install_key is not null;

create table private.blocks (
  id bigserial primary key,
  install_key text,
  user_id uuid references auth.users (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  lifted_at timestamptz,
  check (install_key is not null or user_id is not null)
);
create unique index blocks_active_install_idx on private.blocks (install_key) where lifted_at is null and install_key is not null;
create unique index blocks_active_user_idx on private.blocks (user_id) where lifted_at is null and user_id is not null;

-- The owner's manual pause: 'free' stops free credits, 'all' stops every job.
create table private.ai_switches (
  scope text primary key check (scope in ('free', 'all')),
  paused_until timestamptz not null,
  note text,
  updated_at timestamptz not null default now()
);

revoke all on all tables in schema private from public;
revoke all on all sequences in schema private from public;

-- MARK: Helpers

create function private.error(p_code text, p_status int, p_until timestamptz default null)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'ok', false,
    'code', p_code,
    'status', p_status,
    'until', p_until,
    'retry_after', case when p_until is not null
                        then greatest(1, ceil(extract(epoch from (p_until - now())))::int) end
  ))
$$;

-- Midnight UTC, when the daily breakers and the free credits reset.
create function private.next_utc_day()
returns timestamptz
language sql stable
set search_path = ''
as $$
  select ((now() at time zone 'utc')::date + 1)::timestamp at time zone 'utc'
$$;

create function private.active_block(p_user uuid, p_install text)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (
    select 1 from private.blocks b
     where b.lifted_at is null
       and (b.user_id = p_user or (p_install is not null and b.install_key = p_install))
  )
$$;

create function private.cooldown_until(p_user uuid, p_install text)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select max(c.ends_at) from private.cooldowns c
   where c.lifted_at is null and c.ends_at > now()
     and (c.user_id = p_user or (p_install is not null and c.install_key = p_install))
$$;

-- Records a strike and decides what follows: nothing yet, a cool-down, or a
-- block for the install (the user, without one).
create function private.add_strike(p_user uuid, p_install text, p_source text, p_category text, p_job uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  pol record;
  v_since timestamptz;
  v_user_count int := 0;
  v_install_count int := 0;
  v_ends timestamptz;
  v_cooldowns int;
begin
  select * into pol from public.credit_policy();
  insert into private.strikes (user_id, install_key, source, category, job_id)
    values (p_user, p_install, p_source, p_category, p_job);
  -- Already resting: no cool-down on top of a cool-down.
  if private.cooldown_until(p_user, p_install) is not null then
    return jsonb_build_object('state', 'strike');
  end if;
  -- A cool-down that ended (or was lifted) starts a clean slate.
  select greatest(now() - make_interval(hours => pol.strike_window_hours),
                  coalesce(max(coalesce(c.lifted_at, c.ends_at)), '-infinity'::timestamptz))
    into v_since
    from private.cooldowns c
   where c.user_id = p_user or (p_install is not null and c.install_key = p_install);
  if p_user is not null then
    select count(*) into v_user_count from private.strikes s where s.user_id = p_user and s.created_at > v_since;
  end if;
  if p_install is not null then
    select count(*) into v_install_count from private.strikes s where s.install_key = p_install and s.created_at > v_since;
  end if;
  if greatest(v_user_count, v_install_count) < pol.strikes_for_cooldown then
    return jsonb_build_object('state', 'strike', 'strikes', greatest(v_user_count, v_install_count));
  end if;

  v_ends := now() + make_interval(hours => pol.cooldown_hours);
  insert into private.cooldowns (user_id, install_key, ends_at) values (p_user, p_install, v_ends);
  select count(*) into v_cooldowns from private.cooldowns c
   where c.starts_at > now() - make_interval(days => pol.cooldown_window_days)
     and case when p_install is not null then c.install_key = p_install else c.user_id = p_user end;
  if v_cooldowns >= pol.cooldowns_for_block then
    insert into private.blocks (install_key, user_id, reason)
      values (p_install, case when p_install is null then p_user end, 'repeated_cooldowns')
      on conflict do nothing;
    return jsonb_build_object('state', 'blocked');
  end if;
  return jsonb_build_object('state', 'cooldown', 'until', v_ends);
end $$;

revoke all on all functions in schema private from public;

-- MARK: Admission

create function public.admit_job(
  p_user uuid,
  p_operation text,
  p_endpoint text,
  p_template_id text default null,
  p_outputs int default 1,
  p_input_images int default 0,
  p_retry_of uuid default null,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_install_environment text default null,
  p_ip text default null,
  p_blocked_category text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'utc')::date;
  v_key text;
  v_kind text;
  v_until timestamptz;
  v_strike jsonb;
  v_usage private.ai_usage_daily;
  v_switch_free boolean;
  v_switch_all timestamptz;
  v_is_pro boolean;
  v_count int;
  v_oldest timestamptz;
  v_limit int;
  v_ip_count int;
  v_original public.jobs;
  v_free boolean := false;
  v_cost int;
  v_allow_daily boolean;
  v_paused boolean := false;
  f record;
  v_split jsonb;
  v_job uuid := gen_random_uuid();
  v_est int;
begin
  select * into pol from public.credit_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  select i.kind into v_kind from private.app_installs i where i.key = v_key;

  -- 1-2. Blocked, or resting after repeated safety blocks.
  if private.active_block(p_user, v_key) then
    return private.error('install_blocked', 403);
  end if;
  v_until := private.cooldown_until(p_user, v_key);
  if v_until is not null then
    return private.error('cooldown', 429, v_until);
  end if;

  -- 3. The prompt policy said no: a strike, never a charge.
  if p_blocked_category is not null then
    v_strike := private.add_strike(p_user, v_key, 'prompt', p_blocked_category, null);
    if v_strike->>'state' = 'blocked' then
      return private.error('install_blocked', 403);
    elsif v_strike->>'state' = 'cooldown' then
      return private.error('cooldown', 429, (v_strike->>'until')::timestamptz);
    end if;
    return jsonb_build_object('ok', false, 'code', 'content_blocked', 'status', 422, 'category', p_blocked_category);
  end if;

  -- 4. The owner's switch and the hard breaker.
  select max(s.paused_until) into v_switch_all from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now;
  if v_switch_all is not null then
    return private.error('ai_paused', 503, v_switch_all);
  end if;
  v_switch_free := exists (select 1 from private.ai_switches s where s.scope = 'free' and s.paused_until > v_now);
  insert into private.ai_usage_daily (day) values (v_today) on conflict (day) do nothing;
  select * into v_usage from private.ai_usage_daily where day = v_today for update;
  if v_usage.total_jobs >= pol.all_jobs_daily_cap then
    return private.error('ai_paused', 503, private.next_utc_day());
  end if;

  -- 5. Per-user limits, then requests from one network address across users.
  select * into f from private.funds(p_user, v_key, false);
  v_is_pro := f.is_pro;
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
    insert into private.ip_usage as u (ip_key, hour, requests)
      values (private.keyed_hash('ip', p_ip), date_trunc('hour', v_now), 1)
      on conflict (ip_key, hour) do update set requests = u.requests + 1
      returning u.requests into v_ip_count;
    if v_ip_count > pol.ip_jobs_per_hour then
      return private.error('usage_limit', 429, date_trunc('hour', v_now) + interval '1 hour');
    end if;
  end if;

  -- 6. Likeness Lock: one free retry per recent result, free_retries_daily a
  --    day. The 15 minutes match the app's EditorViewModel.
  if p_retry_of is not null then
    select * into v_original from public.jobs
     where id = p_retry_of and user_id = p_user and operation = p_operation and status = 'completed'
       and not retried and created_at > v_now - interval '15 minutes'
     for update;
    if not found then
      return private.error('retry_unavailable', 409);
    end if;
    select count(*) into v_count from public.jobs
     where user_id = p_user and retry_of is not null and created_at >= v_today::timestamp at time zone 'utc';
    if v_count >= pol.free_retries_daily then
      return private.error('retry_limit', 409, private.next_utc_day());
    end if;
    v_free := v_original.free;
    if v_free and (v_switch_free or v_usage.free_jobs >= pol.free_jobs_daily_cap) then
      return private.error('ai_paused', 503, private.next_utc_day());
    end if;
    v_cost := 0;
  else
    v_cost := greatest(1, p_outputs);
  end if;

  -- 7. Pay: free daily credits (one allowance per App Store install) →
  --    subscription → packs.
  v_allow_daily := not v_is_pro and v_key is not null;
  if v_allow_daily and (v_switch_free or v_usage.free_jobs >= pol.free_jobs_daily_cap
      or (v_kind = 'unverified' and v_usage.unverified_jobs >= pol.unverified_jobs_daily_cap)) then
    v_allow_daily := false;
    v_paused := true;
  end if;
  if v_cost > 0 then
    if (case when v_allow_daily then f.install_daily else 0 end) + f.subscription_credits + f.purchased_credits < v_cost then
      if v_paused and f.install_daily + f.subscription_credits + f.purchased_credits >= v_cost then
        return private.error('ai_paused', 503, private.next_utc_day());
      end if;
      if not v_is_pro and v_key is null and f.subscription_credits + f.purchased_credits < v_cost then
        return private.error(case when p_install_status = 'invalid' then 'app_transaction_invalid'
                                  else 'app_transaction_required' end, 428);
      end if;
      return jsonb_build_object('ok', false, 'code', 'insufficient_credits', 'status', 402,
                                'credits_remaining', private.balance_of(p_user, v_key));
    end if;
  end if;

  -- 8. Book it.
  v_est := greatest(1, p_outputs) * (case when v_is_pro then pol.cost_medium_cents else pol.cost_low_cents end)
         + greatest(0, p_input_images) * pol.cost_input_image_cents;
  if p_retry_of is not null then
    update public.jobs set retried = true, updated_at = v_now where id = p_retry_of;
  elsif v_cost > 0 then
    v_split := private.hold(p_user, v_job, v_cost, v_key,
                            case when v_allow_daily then f.install_daily else 0 end,
                            f.subscription_credits, f.entitlement);
    v_free := (v_split->>'daily')::int > 0;
  end if;
  insert into public.jobs (id, user_id, operation, template_id, endpoint, cost, retry_of, install_key, free, est_cost_cents)
    values (v_job, p_user, p_operation, p_template_id, p_endpoint, v_cost, p_retry_of, v_key, v_free, v_est);
  update private.ai_usage_daily
     set total_jobs = total_jobs + 1,
         free_jobs = free_jobs + case when v_free then 1 else 0 end,
         unverified_jobs = unverified_jobs + case when v_free and v_kind = 'unverified' then 1 else 0 end,
         est_cost_cents = est_cost_cents + v_est
   where day = v_today;
  return jsonb_build_object('ok', true, 'job_id', v_job, 'credits_remaining', private.balance_of(p_user, v_key));
end $$;

-- GET /ai-image: the balance, what it's made of and the numbers the app shows.
create function public.wallet_state(
  p_user uuid,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_install_environment text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
  f record;
  v_until timestamptz;
  v_blocked boolean;
begin
  select * into pol from public.credit_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  select * into f from private.funds(p_user, v_key, true);
  v_blocked := private.active_block(p_user, v_key);
  v_until := private.cooldown_until(p_user, v_key);
  return jsonb_strip_nulls(jsonb_build_object(
    'credits_remaining', f.daily_credits + f.subscription_credits + f.purchased_credits,
    'is_pro', f.is_pro,
    -- 'unverified': no App Store install was verified, so the free part of
    -- the balance is unknown; the app lets the server decide.
    'free_credits', case when f.is_pro then 'pro' when v_key is null then 'unverified' else 'ok' end,
    'ai_status', case when v_blocked then 'blocked' when v_until is not null then 'cooldown' else 'ok' end,
    'cooldown_until', v_until,
    'policy', jsonb_build_object(
      'free_daily', pol.free_daily,
      'pro_monthly', pol.pro_monthly,
      'rollover_cap', pol.pro_rollover_cap,
      'trial_credits', pol.trial_credits,
      'free_retries_daily', pol.free_retries_daily
    )
  ));
end $$;

-- An output the moderation flagged: fail and refund the job (if it still
-- runs) and count a strike against its user and install.
create function public.flag_job(p_job uuid, p_code text, p_message text, p_category text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  j public.jobs;
begin
  select * into j from public.jobs where id = p_job;
  if not found then
    return null;
  end if;
  perform public.fail_job(p_job, p_code, p_message);
  return private.add_strike(j.user_id, j.install_key, 'output', p_category, p_job);
end $$;

-- POST /report: reports_per_day per user (rolling day), job linked only when it's hers.
create function public.file_report(p_user uuid, p_reason text, p_job uuid default null, p_details text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_count int;
  v_oldest timestamptz;
begin
  select * into pol from public.credit_policy();
  select count(*), min(created_at) into v_count, v_oldest from public.reports
   where user_id = p_user and created_at > now() - interval '1 day';
  if v_count >= pol.reports_per_day then
    return private.error('rate_limited', 429, v_oldest + interval '1 day');
  end if;
  insert into public.reports (user_id, job_id, reason, details)
    values (p_user, (select j.id from public.jobs j where j.id = p_job and j.user_id = p_user), p_reason,
            nullif(left(btrim(coalesce(p_details, '')), 500), ''));
  return jsonb_build_object('ok', true);
end $$;

-- MARK: Accounts and cleanup

-- Sign in with Apple: strikes, cool-downs and a user block follow the user
-- into the account (see 20261021 for the credits).
create or replace function public.merge_accounts(p_from uuid, p_to uuid)
returns public.credit_wallets
language plpgsql security definer
set search_path = ''
as $$
declare
  src public.credit_wallets;
  dst public.credit_wallets;
begin
  if p_from = p_to then
    raise exception 'cannot merge an account into itself';
  end if;
  insert into public.credit_wallets (user_id) values (p_to) on conflict (user_id) do nothing;
  perform 1 from public.credit_wallets where user_id in (p_from, p_to) order by user_id for update;
  select * into src from public.credit_wallets where user_id = p_from;

  if src.user_id is not null and src.purchased > 0 then
    update public.credit_wallets set purchased = purchased + src.purchased, updated_at = now() where user_id = p_to;
    insert into public.credit_ledger (user_id, kind, purchased, source_ref)
      values (p_to, 'admin', src.purchased, 'merge:' || p_from)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    update public.credit_wallets set purchased = 0, updated_at = now() where user_id = p_from;
  end if;

  update public.entitlements set user_id = p_to, updated_at = now() where user_id = p_from;
  update public.jobs set user_id = p_to where user_id = p_from;
  update public.credit_ledger set user_id = p_to where user_id = p_from;
  update public.reports set user_id = p_to where user_id = p_from;
  update private.strikes set user_id = p_to where user_id = p_from;
  update private.cooldowns set user_id = p_to where user_id = p_from;
  if not exists (select 1 from private.blocks where user_id = p_to and lifted_at is null) then
    update private.blocks set user_id = p_to where user_id = p_from and lifted_at is null;
  end if;

  select * into dst from public.credit_wallets where user_id = p_to;
  return dst;
end $$;

-- The 20261017 cleanup, plus the abuse data's retention (see the top).
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
  delete from private.ai_usage_daily where day < (now() at time zone 'utc')::date - 90;
  delete from private.ai_switches where paused_until < now() - interval '1 day';
end $$;

-- MARK: Owner tools (SQL editor; backend/README.md "Abuse runbook")

-- Reports, newest first, with what the safety system knows about who sent them.
create function public.ops_reports(p_status text default 'open', p_limit int default 50)
returns table (
  report_id uuid, created_at timestamptz, reason text, details text, status text,
  user_id uuid, job_id uuid, operation text, template_id text, install_key text,
  user_strikes_30d bigint, install_strikes_30d bigint, install_blocked boolean
)
language sql stable security definer
set search_path = ''
as $$
  select r.id, r.created_at, r.reason, r.details, r.status, r.user_id, r.job_id, j.operation, j.template_id, j.install_key,
         (select count(*) from private.strikes s where s.user_id = r.user_id and s.created_at > now() - interval '30 days'),
         (select count(*) from private.strikes s where j.install_key is not null and s.install_key = j.install_key
             and s.created_at > now() - interval '30 days'),
         exists (select 1 from private.blocks b where b.lifted_at is null and b.install_key = j.install_key)
    from public.reports r
    left join public.jobs j on j.id = r.job_id
   where p_status is null or r.status = p_status
   order by r.created_at desc
   limit greatest(1, p_limit)
$$;

create function public.ops_set_report_status(p_report uuid, p_status text)
returns void
language sql security definer
set search_path = ''
as $$
  update public.reports set status = p_status where id = p_report
$$;

-- Who collected strikes lately, per install (or user, without one).
create function public.ops_strikes(p_days int default 7)
returns table (
  install_key text, user_ids uuid[], strikes bigint, prompt_strikes bigint, output_strikes bigint,
  categories text[], last_strike_at timestamptz, cooldowns bigint, cooldown_until timestamptz, blocked boolean
)
language sql stable security definer
set search_path = ''
as $$
  with grouped as (
    select max(s.install_key) as install_key,
           array_remove(array_agg(distinct s.user_id), null) as user_ids,
           count(*) as strikes,
           count(*) filter (where s.source = 'prompt') as prompt_strikes,
           count(*) filter (where s.source = 'output') as output_strikes,
           array_remove(array_agg(distinct s.category), null) as categories,
           max(s.created_at) as last_strike_at
      from private.strikes s
     where s.created_at > now() - make_interval(days => greatest(1, p_days))
     group by coalesce(s.install_key, 'user:' || s.user_id::text)
  )
  select g.install_key, g.user_ids, g.strikes, g.prompt_strikes, g.output_strikes, g.categories, g.last_strike_at,
         (select count(*) from private.cooldowns c
           where c.install_key = g.install_key or (g.install_key is null and c.user_id = any (g.user_ids))),
         (select max(c.ends_at) from private.cooldowns c
           where c.lifted_at is null and c.ends_at > now()
             and (c.install_key = g.install_key or c.user_id = any (g.user_ids))),
         exists (select 1 from private.blocks b
                  where b.lifted_at is null and (b.install_key = g.install_key or b.user_id = any (g.user_ids)))
    from grouped g
   order by g.strikes desc, g.last_strike_at desc
$$;

-- Blocks cloud AI for an install, a user, or the install and user behind a job.
create function public.ops_block(
  p_install text default null, p_user uuid default null, p_job uuid default null, p_reason text default 'owner'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_install text := p_install;
  v_user uuid := p_user;
  v_count int := 0;
begin
  if p_job is not null then
    select j.install_key, j.user_id into v_install, v_user from public.jobs j where j.id = p_job;
    if not found then
      raise exception 'no job %', p_job;
    end if;
  end if;
  if v_install is null and v_user is null then
    raise exception 'name an install, a user or a job';
  end if;
  if v_install is not null then
    insert into private.blocks (install_key, reason) values (v_install, p_reason) on conflict do nothing;
    get diagnostics v_count = row_count;
  end if;
  if v_user is not null then
    insert into private.blocks (user_id, reason) values (v_user, p_reason) on conflict do nothing;
  end if;
  return jsonb_build_object('install_key', v_install, 'user_id', v_user, 'new_install_block', v_count > 0);
end $$;

-- Lifts blocks and running cool-downs for an install and/or a user.
create function public.ops_unblock(p_install text default null, p_user uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_blocks int;
  v_cooldowns int;
begin
  if p_install is null and p_user is null then
    raise exception 'name an install or a user';
  end if;
  update private.blocks set lifted_at = now()
   where lifted_at is null and (install_key = p_install or user_id = p_user);
  get diagnostics v_blocks = row_count;
  update private.cooldowns set lifted_at = now()
   where lifted_at is null and ends_at > now() and (install_key = p_install or user_id = p_user);
  get diagnostics v_cooldowns = row_count;
  return jsonb_build_object('blocks_lifted', v_blocks, 'cooldowns_lifted', v_cooldowns);
end $$;

-- Pauses AI for everyone ('all') or only free credits ('free') for p_hours.
create function public.ops_pause_ai(p_scope text default 'all', p_hours numeric default 1, p_note text default null)
returns jsonb
language sql security definer
set search_path = ''
as $$
  insert into private.ai_switches (scope, paused_until, note, updated_at)
    values (p_scope, now() + make_interval(secs => (p_hours * 3600)::double precision), p_note, now())
    on conflict (scope) do update set paused_until = excluded.paused_until, note = excluded.note, updated_at = now()
  returning jsonb_build_object('scope', scope, 'paused_until', paused_until)
$$;

create function public.ops_resume_ai(p_scope text default null)
returns jsonb
language sql security definer
set search_path = ''
as $$
  with resumed as (
    delete from private.ai_switches where p_scope is null or scope = p_scope returning scope
  )
  select jsonb_build_object('resumed', coalesce(jsonb_agg(scope), '[]'::jsonb)) from resumed
$$;

-- One day at a glance (UTC): jobs, estimated cost, breakers, safety.
create function public.ops_daily_summary(p_day date default (now() at time zone 'utc')::date)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  pol record;
  v_from timestamptz := p_day::timestamp at time zone 'utc';
  v_to timestamptz := (p_day + 1)::timestamp at time zone 'utc';
  v_usage private.ai_usage_daily;
  v_jobs jsonb;
  v_errors jsonb;
  v_billed bigint;
begin
  select * into pol from public.credit_policy();
  select * into v_usage from private.ai_usage_daily where day = p_day;
  select jsonb_build_object(
           'total', count(*),
           'free', count(*) filter (where free),
           'paid', count(*) filter (where not free and cost > 0),
           'retries', count(*) filter (where retry_of is not null),
           'completed', count(*) filter (where status = 'completed'),
           'failed', count(*) filter (where status = 'failed'),
           'cancelled', count(*) filter (where status = 'cancelled'),
           'running', count(*) filter (where status in ('queued', 'processing')),
           'installs', count(distinct install_key),
           'users', count(distinct user_id))
    into v_jobs
    from public.jobs where created_at >= v_from and created_at < v_to;
  select coalesce(jsonb_object_agg(code, n), '{}'::jsonb) into v_errors
    from (select coalesce(error_code, 'unknown') as code, count(*) as n
            from public.jobs where created_at >= v_from and created_at < v_to and status = 'failed'
           group by 1) e;
  -- What the provider most likely billed: results, including blocked ones.
  select coalesce(sum(est_cost_cents), 0) into v_billed
    from public.jobs
   where created_at >= v_from and created_at < v_to
     and (status = 'completed'
          or error_code in ('content_blocked', 'safety_check_failed', 'undelivered', 'unconfirmed'));
  return jsonb_build_object(
    'day', p_day,
    'jobs', v_jobs,
    'failures_by_code', v_errors,
    'estimated_cost_usd', jsonb_build_object(
      'billed', round(v_billed / 100.0, 2),
      'admitted_upper_bound', round(coalesce(v_usage.est_cost_cents, 0) / 100.0, 2)),
    'breakers', jsonb_build_object(
      'all_jobs', coalesce(v_usage.total_jobs, 0), 'all_jobs_cap', pol.all_jobs_daily_cap,
      'free_jobs', coalesce(v_usage.free_jobs, 0), 'free_jobs_cap', pol.free_jobs_daily_cap,
      'unverified_jobs', coalesce(v_usage.unverified_jobs, 0), 'unverified_jobs_cap', pol.unverified_jobs_daily_cap,
      'switches', (select coalesce(jsonb_object_agg(scope, paused_until), '{}'::jsonb)
                     from private.ai_switches where paused_until > now())),
    'safety', jsonb_build_object(
      'strikes', (select count(*) from private.strikes where created_at >= v_from and created_at < v_to),
      'prompt_strikes', (select count(*) from private.strikes
                          where source = 'prompt' and created_at >= v_from and created_at < v_to),
      'output_strikes', (select count(*) from private.strikes
                          where source = 'output' and created_at >= v_from and created_at < v_to),
      'cooldowns_started', (select count(*) from private.cooldowns where starts_at >= v_from and starts_at < v_to),
      'cooldowns_active', (select count(*) from private.cooldowns where lifted_at is null and ends_at > now()),
      'blocks_new', (select count(*) from private.blocks where created_at >= v_from and created_at < v_to),
      'blocks_active', (select count(*) from private.blocks where lifted_at is null)),
    'reports', jsonb_build_object(
      'new', (select count(*) from public.reports where created_at >= v_from and created_at < v_to),
      'open', (select count(*) from public.reports where status = 'open')),
    'installs_seen', (select count(*) from private.app_installs where last_seen_at >= v_from and last_seen_at < v_to),
    'top_installs', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select left(install_key, 12) as install, count(*) as jobs from public.jobs
         where created_at >= v_from and created_at < v_to and install_key is not null
         group by install_key order by count(*) desc limit 5) t),
    'top_ips', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select left(ip_key, 12) as ip, sum(requests) as requests from private.ip_usage
         where hour >= v_from and hour < v_to
         group by ip_key order by sum(requests) desc limit 5) t)
  );
end $$;

-- MARK: Privileges

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.admit_job(uuid, text, text, text, int, int, uuid, text, text, text, text, text)',
    'public.wallet_state(uuid, text, text, text)',
    'public.flag_job(uuid, text, text, text)',
    'public.file_report(uuid, text, uuid, text)',
    'public.merge_accounts(uuid, uuid)',
    'public.sweep_jobs()',
    'public.ops_reports(text, int)',
    'public.ops_set_report_status(uuid, text)',
    'public.ops_strikes(int)',
    'public.ops_block(text, uuid, uuid, text)',
    'public.ops_unblock(text, uuid)',
    'public.ops_pause_ai(text, numeric, text)',
    'public.ops_resume_ai(text)',
    'public.ops_daily_summary(date)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
