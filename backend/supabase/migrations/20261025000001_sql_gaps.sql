-- SQL gaps (docs/AI-TODO.md, section 1, item 8). Replaces functions in place;
-- the migrations that made them stay as they were deployed.
--
--   * admit_job: the daily Likeness Lock count (free_retries_daily) counts
--     only retries that were not refunded: queued, processing or completed.
--     A failed retry (provider error, timeout, safety block, a result refunded
--     as undelivered or unconfirmed) or a cancelled one gives its slot back.
--     The rate limits and one retry per result (jobs.retried) still apply.
--   * flag_job: a job the user cancelled (status 'cancelled', set only by
--     cancel_job) is no strike when its result comes back flagged. The row is
--     locked first, so a cancel arriving at the same time lands before or after.
--   * wallet_state: a five-argument form takes the client address (the same
--     ipBucket that admit_job gets), so a cool-down or block kept on the address
--     of an install without a verified App Store transaction shows in the
--     balance. The four-argument form stays for older callers and passes no
--     address: a default on p_ip would make every shorter call ambiguous.

-- MARK: Admission

create or replace function public.admit_job(
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
  v_abuse text;
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
  v_attempt uuid;
  v_est int;
begin
  select * into pol from public.credit_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  select i.kind into v_kind from private.app_installs i where i.key = v_key;
  -- Strikes, cool-downs and blocks follow the verified install or, without one,
  -- the address (a salted hash, the same key as ip_usage). Credits use v_key only.
  v_abuse := coalesce(v_key, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);

  -- 1-2. Blocked, or resting after repeated safety blocks.
  if private.active_block(p_user, v_abuse) then
    return private.error('install_blocked', 403);
  end if;
  v_until := private.cooldown_until(p_user, v_abuse);
  if v_until is not null then
    return private.error('cooldown', 429, v_until);
  end if;

  -- 3. The owner's switch and the hard breaker come before the prompt check,
  --    so a paused AI takes no request at all, blocked prompts included.
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

  -- 4. Per-user limits, then requests from one network address across users.
  --    A request a limit refuses writes no strike.
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

  -- 5. The prompt policy said no: a strike, never a charge. The attempt is
  --    booked free, so it counts toward the limits above and the owner can see it.
  if p_blocked_category is not null then
    insert into public.jobs (user_id, operation, template_id, endpoint, status, error_code, install_key)
      values (p_user, p_operation, p_template_id, p_endpoint, 'failed', 'content_blocked', v_abuse)
      returning id into v_attempt;
    v_strike := private.add_strike(p_user, v_abuse, 'prompt', p_blocked_category, v_attempt);
    if v_strike->>'state' = 'blocked' then
      return private.error('install_blocked', 403);
    elsif v_strike->>'state' = 'cooldown' then
      return private.error('cooldown', 429, (v_strike->>'until')::timestamptz);
    end if;
    return jsonb_build_object('ok', false, 'code', 'content_blocked', 'status', 422, 'category', p_blocked_category);
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
    -- Only retries she got or is still waiting for: a refunded one (failed,
    -- timed out, never delivered, cancelled) gives its slot back.
    select count(*) into v_count from public.jobs
     where user_id = p_user and retry_of is not null and created_at >= v_today::timestamp at time zone 'utc'
       and status in ('queued', 'processing', 'completed');
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

  -- 8. Book it. The job carries the address key for installs without a verified
  --    one, so flag_job and ops_block act on the same install.
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
    values (v_job, p_user, p_operation, p_template_id, p_endpoint, v_cost, p_retry_of, v_abuse, v_free, v_est);
  update private.ai_usage_daily
     set total_jobs = total_jobs + 1,
         free_jobs = free_jobs + case when v_free then 1 else 0 end,
         unverified_jobs = unverified_jobs + case when v_free and v_kind = 'unverified' then 1 else 0 end,
         est_cost_cents = est_cost_cents + v_est
   where day = v_today;
  return jsonb_build_object('ok', true, 'job_id', v_job, 'credits_remaining', private.balance_of(p_user, v_key));
end $$;

-- MARK: Strikes

-- An output the moderation flagged: fail and refund the job (if it still
-- runs) and count a strike against its user and install. Null, and no strike,
-- when there is no such job or she cancelled it before the result came back.
create or replace function public.flag_job(p_job uuid, p_code text, p_message text, p_category text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  j public.jobs;
begin
  select * into j from public.jobs where id = p_job for update;
  if not found or j.status = 'cancelled' then
    return null;
  end if;
  perform public.fail_job(p_job, p_code, p_message);
  return private.add_strike(j.user_id, j.install_key, 'output', p_category, p_job);
end $$;

-- MARK: Balance

-- GET /ai-image: the balance, what it's made of and the numbers the app shows.
-- Strikes, cool-downs and blocks follow the verified install or, without one,
-- the address (a salted hash, the same key as admit_job). Credits use the
-- install only.
create function public.wallet_state(
  p_user uuid,
  p_app_transaction_id text,
  p_install_status text,
  p_install_environment text,
  p_ip text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
  v_abuse text;
  f record;
  v_until timestamptz;
  v_blocked boolean;
begin
  select * into pol from public.credit_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  v_abuse := coalesce(v_key, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);
  select * into f from private.funds(p_user, v_key, true);
  v_blocked := private.active_block(p_user, v_abuse);
  v_until := private.cooldown_until(p_user, v_abuse);
  return jsonb_strip_nulls(jsonb_build_object(
    'credits_remaining', f.daily_credits + f.subscription_credits + f.purchased_credits,
    'is_pro', f.is_pro,
    -- 'unverified': no App Store install was verified, so the free part of
    -- the balance is unknown; the app lets the server decide.
    'free_credits', case when f.is_pro then 'pro' when v_key is null then 'unverified' else 'ok' end,
    'ai_status', case when v_blocked then 'blocked' when v_until is not null then 'cooldown' else 'ok' end,
    'cooldown_until', v_until,
    'cooldown_seconds', case when v_until is not null then greatest(1, ceil(extract(epoch from (v_until - now())))::int) end,
    'policy', jsonb_build_object(
      'free_daily', pol.free_daily,
      'pro_monthly', pol.pro_monthly,
      'rollover_cap', pol.pro_rollover_cap,
      'trial_credits', pol.trial_credits,
      'free_retries_daily', pol.free_retries_daily
    )
  ));
end $$;

-- The call without an address (20261022), for callers that predate it.
create or replace function public.wallet_state(
  p_user uuid,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_install_environment text default null
)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select public.wallet_state(p_user, p_app_transaction_id, p_install_status, p_install_environment, null::text)
$$;

-- MARK: Privileges

revoke execute on function public.wallet_state(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.wallet_state(uuid, text, text, text, text) to service_role;
