-- The launch breakers leave room for paid jobs (20261029000000): free jobs stop
-- at 60 (unverified at 10), every job at 400, so Pro members and pack buyers
-- keep working long after the free breaker trips. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

do $$
declare
  pol record;
begin
  select * into pol from public.credit_policy();
  assert (pol.free_jobs_daily_cap, pol.unverified_jobs_daily_cap, pol.all_jobs_daily_cap) = (60, 10, 400),
    format('the breakers: %s', row_to_json(pol));
  assert pol.all_jobs_daily_cap - pol.free_jobs_daily_cap >= 340, 'paid jobs always keep 340 a day';
  -- Everything else as 20261027000001 left it.
  assert (pol.free_daily, pol.pro_monthly, pol.pro_rollover_cap, pol.trial_credits, pol.free_retries_daily)
         = (2, 80, 160, 20, 3), format('credits unchanged: %s', row_to_json(pol));
  assert (pol.jobs_per_minute_free, pol.jobs_per_minute_pro, pol.jobs_per_hour_free, pol.jobs_per_hour_pro,
          pol.jobs_per_day_free, pol.jobs_per_day_pro, pol.ip_jobs_per_hour, pol.reports_per_day)
         = (6, 20, 30, 60, 100, 200, 120, 10), format('rate limits unchanged: %s', row_to_json(pol));
  assert (pol.strikes_for_cooldown, pol.strike_window_hours, pol.cooldown_hours, pol.cooldowns_for_block,
          pol.cooldown_window_days, pol.install_retention_days) = (3, 24, 24, 3, 30, 30),
    format('strikes unchanged: %s', row_to_json(pol));
  assert (pol.cost_low_cents, pol.cost_medium_cents, pol.cost_input_image_cents) = (4, 6, 1),
    format('costs unchanged: %s', row_to_json(pol));
  assert not has_function_privilege('authenticated', 'public.credit_policy()', 'execute'), 'still server only';
  assert (select proconfig::text from pg_proc where oid = 'public.credit_policy()'::regprocedure) like '%search_path=%',
    'still pins its search_path';
end $$;

do $$
declare
  free_user uuid := gen_random_uuid();
  buyer uuid := gen_random_uuid();
  pro uuid := gen_random_uuid();
  atid text := 'atid-paid-room-' || gen_random_uuid();
  v_today date := (now() at time zone 'utc')::date;
  saved private.ai_usage_daily;
  r jsonb;
begin
  perform public.ops_resume_ai();
  insert into auth.users (id) values (free_user), (buyer), (pro);
  perform public.grant_pack(buyer, 5, 'tx-paid-room-' || buyer);
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('otx-paid-room-' || pro, pro, 'app.glowlit.pro.monthly', now() + interval '1 month');
  insert into private.ai_usage_daily (day) values (v_today) on conflict (day) do nothing;
  select * into saved from private.ai_usage_daily where day = v_today;

  -- The free breaker is full and the day has had 120 jobs, the old hard cap.
  update private.ai_usage_daily set free_jobs = 60, total_jobs = 120 where day = v_today;
  r := public.admit_job(free_user, 'magic_edit', 'test', p_input_images => 1,
                        p_app_transaction_id => atid, p_install_status => 'verified');
  assert r ->> 'code' = 'ai_paused' and (r ->> 'status')::int = 503, format('free credits wait: %s', r);
  r := public.admit_job(buyer, 'magic_edit', 'test', p_input_images => 1);
  assert (r ->> 'ok')::boolean and not (select free from public.jobs where id = (r ->> 'job_id')::uuid),
    format('a pack buyer goes on: %s', r);
  r := public.admit_job(pro, 'text_to_image', 'test');
  assert (r ->> 'ok')::boolean, format('Pro goes on: %s', r);
  assert (select (total_jobs, free_jobs) = (122, 60) from private.ai_usage_daily where day = v_today),
    'paid jobs count toward the day, not toward the free breaker';

  -- Paid jobs run up to the hard cap, which still stops everyone.
  update private.ai_usage_daily set total_jobs = 399 where day = v_today;
  r := public.admit_job(buyer, 'magic_edit', 'test', p_input_images => 1);
  assert (r ->> 'ok')::boolean, format('the 400th job: %s', r);
  r := public.admit_job(pro, 'text_to_image', 'test');
  assert r ->> 'code' = 'ai_paused' and (r ->> 'retry_after')::int > 0, format('the 401st: %s', r);

  update private.ai_usage_daily
     set total_jobs = saved.total_jobs + 3, free_jobs = saved.free_jobs, unverified_jobs = saved.unverified_jobs
   where day = v_today;
  delete from private.app_installs where key = private.keyed_hash('app_transaction', atid);
  delete from auth.users where id in (free_user, buyer, pro);
end $$;

select 'all paid jobs room tests passed' as result;
