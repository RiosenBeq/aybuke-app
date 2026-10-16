-- Claude's capacity goes to the safety checks first (20261103000000): the
-- install proof in admit_assist() (its own bucket, blocks and cool-downs by
-- install), the shared cap without one, everyone's ceilings a minute, an hour
-- and a day, the quiet time after a failed result check, and job_admissible(),
-- the polish's read-only look at whether admit_job() could take a job. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure and cleans
-- up after itself.
\set ON_ERROR_STOP on

-- Server only, and the numbers.
do $$
declare
  fn text;
  pol record;
begin
  foreach fn in array array[
    'public.assist_policy()',
    'public.admit_assist(uuid, text, text, text, text)',
    'public.admit_assist(uuid, text, text)',
    'public.job_admissible(uuid, text, int, uuid, text, text, text)'
  ] loop
    assert not has_function_privilege('anon', fn, 'execute'), fn || ': server only (anon)';
    assert not has_function_privilege('authenticated', fn, 'execute'), fn || ': server only (authenticated)';
    assert has_function_privilege('service_role', fn, 'execute'), fn || ': the functions call it';
  end loop;
  assert not has_table_privilege('authenticated', 'private.assist_ceilings', 'select'), 'no client reads the counts';
  assert (select relrowsecurity from pg_class where oid = 'private.assist_ceilings'::regclass), 'RLS is on';
  assert (select provolatile from pg_proc
           where oid = 'public.job_admissible(uuid, text, int, uuid, text, text, text)'::regprocedure) = 's',
    'job_admissible() is stable: it can''t write';

  select * into pol from public.assist_policy();
  assert (pol.user_per_hour, pol.ip_per_hour, pol.install_per_hour, pol.unverified_per_hour) = (60, 200, 60, 30),
    format('per account, address and install, and without one: %s', row_to_json(pol));
  assert (pol.all_per_minute, pol.all_per_hour, pol.all_per_day, pol.quiet_after_check_error_minutes)
         = (20, 200, 1000, 5), format('everyone''s ceilings: %s', row_to_json(pol));
end $$;

-- A verified install: its own bucket across its accounts, and blocks and
-- cool-downs follow it. Without one, the address stands in, as in admit_job().
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  tx text := 'atid-assist-' || gen_random_uuid();
  v_key text;
  r jsonb;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker set last_error_at = null;
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into auth.users (id) values (a), (b);
  v_key := private.keyed_hash('app_transaction', tx);

  for i in 1..40 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(a, '203.0.113.150', 'assist', tx, 'verified');
    assert r = '{"ok": true}'::jsonb, format('a, request %s: %s', i, r);
  end loop;
  for i in 1..20 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(b, '203.0.113.151', 'assist', tx, 'verified');
    assert (r->>'ok')::boolean, format('b, request %s: %s', i, r);
  end loop;
  delete from private.assist_ceilings;
  r := public.admit_assist(b, '203.0.113.151', 'assist', tx, 'verified');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429
     and (r->>'until')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    format('the 61st on one install, from a second account: %s', r);
  r := public.admit_assist(b, '203.0.113.151', 'polish', tx, 'verified');
  assert (r->>'ok')::boolean, format('the polish has its own install count: %s', r);
  assert (select requests from private.assist_usage where kind = 'assist' and bucket = v_key) = 61,
    'counted under the install''s key (a refused request too)';
  assert not exists (select 1 from private.assist_usage where bucket = tx), 'never the raw app transaction id';
  assert not exists (select 1 from private.assist_ceilings where scope = 'unverified_hour'),
    'a verified install never takes a place under the shared cap';

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  perform public.ops_block(p_install => v_key, p_reason => 'test');
  r := public.admit_assist(a, '203.0.113.150', 'assist', tx, 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503, format('blocked install: %s', r);
  r := public.admit_assist(b, '203.0.113.151', 'polish', tx, 'verified');
  assert r->>'code' = 'assist_unavailable', format('every account on it, the polish too: %s', r);
  perform public.ops_unblock(p_install => v_key);
  insert into private.cooldowns (install_key, ends_at) values (v_key, now() + interval '1 hour');
  r := public.admit_assist(b, '203.0.113.151', 'assist', tx, 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'retry_after')::int between 3500 and 3600,
    format('a resting install: %s', r);
  perform public.ops_unblock(p_install => v_key);
  assert not exists (select 1 from private.assist_usage), 'nothing counted while blocked or resting';

  perform public.ops_block(p_install => private.keyed_hash('ip', '203.0.113.152'), p_reason => 'test');
  r := public.admit_assist(a, '203.0.113.152', 'assist');
  assert r->>'code' = 'assist_unavailable', format('without install proof, a blocked address: %s', r);
  r := public.admit_assist(a, '203.0.113.152', 'assist', tx, 'invalid');
  assert r->>'code' = 'assist_unavailable', format('an invalid proof is no proof: %s', r);
  r := public.admit_assist(a, '203.0.113.152', 'assist', tx, 'verified');
  assert (r->>'ok')::boolean, format('a verified install is keyed by the install: %s', r);
  perform public.ops_unblock(p_install => private.keyed_hash('ip', '203.0.113.152'));

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from private.blocks where install_key in (v_key, private.keyed_hash('ip', '203.0.113.152'));
  delete from private.cooldowns where install_key = v_key;
  delete from auth.users where id in (a, b);
end $$;

-- Without a verified install: 30 an hour shared by everyone, both kinds. Then
-- everyone's ceilings: 20 a minute, 200 an hour, 1,000 a day. They count only
-- what they admit, and give back what a later one refused.
do $$
declare
  v_users uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  r jsonb;
  v_minute timestamptz := date_trunc('minute', now());
  v_hour timestamptz := date_trunc('hour', now());
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  places text;
begin
  update private.safety_breaker set last_error_at = null;
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into auth.users (id) select unnest(v_users);

  for i in 1..30 loop
    delete from private.assist_ceilings where scope = 'all_minute';
    r := public.admit_assist(v_users[1 + i % 3], '198.51.100.' || i, case when i % 2 = 0 then 'polish' else 'assist' end);
    assert (r->>'ok')::boolean, format('unverified, request %s: %s', i, r);
  end loop;
  delete from private.assist_ceilings where scope = 'all_minute';
  r := public.admit_assist(v_users[1], '198.51.100.99', 'assist', null, 'invalid');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503
     and (r->>'until')::timestamptz = v_hour + interval '1 hour', format('the 31st without a verified install: %s', r);
  r := public.admit_assist(v_users[2], '198.51.100.98', 'polish');
  assert r->>'code' = 'assist_unavailable', format('the polish shares it (the three-argument form): %s', r);
  assert (select requests from private.assist_ceilings where scope = 'unverified_hour') = 30,
    'a refused request takes no place';
  r := public.admit_assist(v_users[1], '198.51.100.99', 'assist', 'atid-ceiling-0', 'verified');
  assert (r->>'ok')::boolean, format('a verified install still gets in: %s', r);

  -- 20 a minute for everyone.
  delete from private.assist_ceilings;
  for i in 1..20 loop
    r := public.admit_assist(v_users[1 + i % 3], '192.0.2.' || i, 'assist', 'atid-ceiling-' || i, 'verified');
    assert (r->>'ok')::boolean, format('request %s this minute: %s', i, r);
  end loop;
  r := public.admit_assist(v_users[1], '192.0.2.50', 'polish', 'atid-ceiling-50', 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'until')::timestamptz = v_minute + interval '1 minute'
     and (r->>'retry_after')::int between 1 and 60, format('the 21st this minute: %s', r);
  r := public.admit_assist(v_users[2], '192.0.2.51', 'assist');
  assert r->>'code' = 'assist_unavailable', format('unverified too: %s', r);
  select string_agg(scope || '=' || requests, ' ' order by scope) into places from private.assist_ceilings;
  assert places = 'all_day=20 all_hour=20 all_minute=20 unverified_hour=0',
    format('only the admitted ones counted, the shared place given back: %s', places);

  -- 200 an hour.
  update private.assist_ceilings set requests = 0 where scope = 'all_minute';
  update private.assist_ceilings set requests = 200 where scope = 'all_hour';
  r := public.admit_assist(v_users[3], '192.0.2.52', 'assist', 'atid-ceiling-52', 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'until')::timestamptz = v_hour + interval '1 hour',
    format('the 201st this hour: %s', r);
  assert (select requests from private.assist_ceilings where scope = 'all_minute') = 0, 'the minute''s place given back';

  -- 1,000 a UTC day.
  update private.assist_ceilings set requests = 0 where scope = 'all_hour';
  update private.assist_ceilings set requests = 1000 where scope = 'all_day' and period = v_day;
  r := public.admit_assist(v_users[3], '192.0.2.53', 'assist', 'atid-ceiling-53', 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'until')::timestamptz = private.next_utc_day(),
    format('the 1,001st today: %s', r);
  assert (select sum(requests) from private.assist_ceilings where scope in ('all_minute', 'all_hour')) = 0,
    'the minute''s and the hour''s places given back';
  update private.assist_ceilings set requests = 999 where scope = 'all_day';
  r := public.admit_assist(v_users[3], '192.0.2.53', 'assist', 'atid-ceiling-53', 'verified');
  assert (r->>'ok')::boolean, format('the 1,000th: %s', r);

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = any (v_users);
end $$;

-- A failed result check: no writing help or polish for 5 minutes, so the
-- safety checks have Claude to themselves. Nothing is counted meanwhile.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into auth.users (id) values (u);
  update private.safety_breaker set last_error_at = now() - interval '1 minute';
  r := public.admit_assist(u, '203.0.113.170', 'assist', 'atid-quiet', 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503
     and (r->>'until')::timestamptz = now() + interval '4 minutes' and (r->>'retry_after')::int between 239 and 240,
    format('a minute after a failed check: %s', r);
  r := public.admit_assist(u, '203.0.113.170', 'polish');
  assert r->>'code' = 'assist_unavailable', format('the polish waits too: %s', r);
  assert not exists (select 1 from private.assist_usage) and not exists (select 1 from private.assist_ceilings),
    'nothing counted';
  update private.safety_breaker set last_error_at = now() - interval '6 minutes';
  r := public.admit_assist(u, '203.0.113.170', 'assist', 'atid-quiet', 'verified');
  assert (r->>'ok')::boolean, format('quiet for 5 minutes, then back: %s', r);

  -- note_safety_check_error() sets it (a result check that couldn't run).
  update private.safety_breaker set last_error_at = null, recent_errors = '{}';
  perform public.note_safety_check_error('HTTP 529 overloaded_error');
  r := public.admit_assist(u, '203.0.113.170', 'assist', 'atid-quiet', 'verified');
  assert r->>'code' = 'assist_unavailable', format('right after a reported error: %s', r);

  update private.safety_breaker set last_error_at = null, recent_errors = '{}';
  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = u;
end $$;

-- job_admissible(): admit_job()'s answer without booking anything.
do $$
declare
  u uuid := gen_random_uuid();
  nobody uuid := gen_random_uuid();
  buyer uuid := gen_random_uuid();
  pro uuid := gen_random_uuid();
  tx text := 'atid-admissible-' || gen_random_uuid();
  v_key text;
  v_today date := (now() at time zone 'utc')::date;
  saved private.ai_usage_daily;
  v_job uuid;
  v_rows bigint;
  r jsonb;
begin
  perform public.ops_resume_ai();
  insert into auth.users (id) values (u), (nobody), (buyer), (pro);
  v_key := private.keyed_hash('app_transaction', tx);
  perform public.grant_pack(buyer, 2, 'tx-admissible-' || buyer);
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at, credits, credits_period_start)
    values ('otx-admissible-' || pro, pro, 'app.glowlit.pro.monthly', now() + interval '1 month', 0,
            now() - interval '3 days');
  insert into private.ai_usage_daily (day) values (v_today) on conflict (day) do nothing;
  select * into saved from private.ai_usage_daily where day = v_today;
  update private.ai_usage_daily set free_jobs = 0, unverified_jobs = 0, total_jobs = 0 where day = v_today;

  -- A new install has today's free credits; nothing is recorded to say so.
  select count(*) into v_rows from private.app_installs;
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified', '203.0.113.180');
  assert r = '{"ok": true}'::jsonb, format('a new install: %s', r);
  assert (select count(*) from private.app_installs) = v_rows, 'no install recorded';
  assert not exists (select 1 from private.ip_usage where ip_key = private.keyed_hash('ip', '203.0.113.180')),
    'no address counted';
  assert not exists (select 1 from public.credit_wallets where user_id = u), 'no wallet made';
  assert not exists (select 1 from public.jobs where user_id = u), 'no job booked';

  -- What she can pay with.
  r := public.job_admissible(nobody, 'text_to_image', 1, null, null, 'missing', '203.0.113.181');
  assert r->>'code' = 'app_transaction_required' and (r->>'status')::int = 428, format('no proof, nothing bought: %s', r);
  r := public.job_admissible(nobody, 'text_to_image', 1, null, 'x', 'invalid');
  assert r->>'code' = 'app_transaction_invalid', format('a proof Apple didn''t sign: %s', r);
  r := public.job_admissible(buyer, 'text_to_image');
  assert (r->>'ok')::boolean, format('a pack pays: %s', r);
  r := public.job_admissible(buyer, 'text_to_image', 3);
  assert r->>'code' = 'app_transaction_required',
    format('three images, two credits: as admit_job(), a verified download''s free credits could help: %s', r);
  r := public.job_admissible(pro, 'text_to_image');
  assert r->>'code' = 'insufficient_credits', format('Pro with this month''s credits spent: %s', r);
  update public.entitlements set credits_period_start = now() - interval '1 month 1 day' where user_id = pro;
  r := public.job_admissible(pro, 'text_to_image');
  assert (r->>'ok')::boolean, format('Pro with a new month due: %s', r);
  insert into private.app_installs (key, kind, daily, daily_period) values (v_key, 'app_store', 0, v_today);
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert r->>'code' = 'insufficient_credits', format('today''s free credits used: %s', r);
  update private.app_installs set daily_period = v_today - 1 where key = v_key;
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert (r->>'ok')::boolean, format('a new UTC day refills them: %s', r);

  -- A free retry costs nothing: the original decides.
  update private.app_installs set daily = 0, daily_period = v_today where key = v_key;
  insert into public.jobs (user_id, operation, endpoint, status, free)
    values (u, 'magic_edit', 'test', 'completed', true) returning id into v_job;
  r := public.job_admissible(u, 'magic_edit', 1, v_job, tx, 'verified');
  assert (r->>'ok')::boolean, format('a retry with no credits left: %s', r);
  r := public.job_admissible(u, 'text_to_image', 1, v_job, tx, 'verified');
  assert r->>'code' = 'retry_unavailable', format('not a retry of that job: %s', r);
  update public.jobs set retried = true where id = v_job;
  r := public.job_admissible(u, 'magic_edit', 1, v_job, tx, 'verified');
  assert r->>'code' = 'retry_unavailable', format('retried already: %s', r);
  delete from public.jobs where user_id = u;
  update private.app_installs set daily = 2 where key = v_key;

  -- The breakers, pauses, blocks and cool-downs.
  update private.ai_usage_daily set free_jobs = 60 where day = v_today;
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert r->>'code' = 'ai_paused', format('the free breaker: %s', r);
  r := public.job_admissible(buyer, 'magic_edit');
  assert (r->>'ok')::boolean, format('a paid job goes on: %s', r);
  update private.ai_usage_daily set free_jobs = 0, total_jobs = 400 where day = v_today;
  r := public.job_admissible(buyer, 'magic_edit');
  assert r->>'code' = 'ai_paused' and (r->>'until')::timestamptz = private.next_utc_day(), format('the hard breaker: %s', r);
  update private.ai_usage_daily set total_jobs = 0 where day = v_today;
  perform public.ops_pause_ai('all', 1, 'test');
  r := public.job_admissible(buyer, 'magic_edit');
  assert r->>'code' = 'ai_paused' and (r->>'status')::int = 503, format('paused: %s', r);
  perform public.ops_resume_ai();
  perform public.ops_block(p_install => v_key, p_reason => 'test');
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert r->>'code' = 'install_blocked', format('a blocked install: %s', r);
  perform public.ops_unblock(p_install => v_key);
  insert into private.cooldowns (user_id, ends_at) values (u, now() + interval '2 hours');
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert r->>'code' = 'cooldown' and (r->>'status')::int = 429, format('resting: %s', r);
  perform public.ops_unblock(p_user => u);

  -- The rate limits, as admit_job() counts them.
  insert into public.jobs (user_id, operation, endpoint, status, error_code)
    select u, 'magic_edit', 'test', 'failed', 'content_blocked' from generate_series(1, 6);
  r := public.job_admissible(u, 'magic_edit', 1, null, tx, 'verified');
  assert r->>'code' = 'rate_limited', format('6 a minute for free members: %s', r);
  delete from public.jobs where user_id = u;
  insert into private.ip_usage (ip_key, hour, requests)
    values (private.keyed_hash('ip', '203.0.113.182'), date_trunc('hour', now()), 120);
  r := public.job_admissible(buyer, 'magic_edit', 1, null, null, 'missing', '203.0.113.182');
  assert r->>'code' = 'usage_limit', format('120 an hour per address: %s', r);
  delete from private.ip_usage where ip_key = private.keyed_hash('ip', '203.0.113.182');

  update private.ai_usage_daily
     set free_jobs = saved.free_jobs, unverified_jobs = saved.unverified_jobs, total_jobs = saved.total_jobs
   where day = v_today;
  delete from private.app_installs where key = v_key;
  delete from private.blocks where install_key = v_key or user_id = u;
  delete from private.cooldowns where user_id = u;
  delete from public.entitlements where user_id = pro;
  delete from auth.users where id in (u, nobody, buyer, pro);
end $$;

-- sweep_jobs() deletes the ceilings' counts after a day.
do $$
begin
  insert into private.assist_ceilings (scope, period, requests) values
    ('all_hour', date_trunc('hour', now()) - interval '25 hours', 3),
    ('all_minute', date_trunc('minute', now()) - interval '2 hours', 4);
  perform public.sweep_jobs();
  assert not exists (select 1 from private.assist_ceilings where scope = 'all_hour'), 'a day old: gone';
  assert exists (select 1 from private.assist_ceilings where scope = 'all_minute'), 'recent: kept';
  delete from private.assist_ceilings;
end $$;

select 'all assist ceiling tests passed' as result;
