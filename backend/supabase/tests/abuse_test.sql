-- Abuse controls: rate limits, breakers, strikes, cool-downs, blocks, free
-- retries, report limits, owner tools and retention. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000d2'),
  ('00000000-0000-0000-0000-0000000000d3'),
  ('00000000-0000-0000-0000-0000000000d4'),
  ('00000000-0000-0000-0000-0000000000d5'),
  ('00000000-0000-0000-0000-0000000000d6'),
  ('00000000-0000-0000-0000-0000000000d7'),
  ('00000000-0000-0000-0000-0000000000d8'),
  ('00000000-0000-0000-0000-0000000000d9'),
  ('00000000-0000-0000-0000-000000000d10'),
  ('00000000-0000-0000-0000-000000000d11'),
  ('00000000-0000-0000-0000-000000000d12'),
  ('00000000-0000-0000-0000-000000000d13'),
  ('00000000-0000-0000-0000-000000000d14'),
  ('00000000-0000-0000-0000-000000000d15'),
  ('00000000-0000-0000-0000-000000000d16'),
  ('00000000-0000-0000-0000-000000000d17'),
  ('00000000-0000-0000-0000-000000000d18'),
  ('00000000-0000-0000-0000-000000000d19'),
  ('00000000-0000-0000-0000-000000000d20');

-- 1. Per-user limits: 6 a minute, 30 an hour and 100 a day on the free tier.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d1';
  r jsonb;
begin
  perform public.grant_pack(u, 300, 'tx-abuse-1');
  for i in 1..6 loop
    r := public.admit_job(u, 'text_to_image', 'test');
    assert (r->>'ok')::boolean, format('job %s: %s', i, r);
  end loop;
  r := public.admit_job(u, 'text_to_image', 'test');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('7th in a minute: %s', r);
  assert (r->>'retry_after')::int between 1 and 60, format('retry soon: %s', r);
  assert (select purchased from public.credit_wallets where user_id = u) = 294, 'a refused job costs nothing';

  update public.jobs set created_at = now() - interval '10 minutes' where user_id = u;
  insert into public.jobs (user_id, operation, endpoint, cost, status, created_at)
    select u, 'text_to_image', 'test', 1, 'completed', now() - interval '20 minutes' from generate_series(1, 24);
  r := public.admit_job(u, 'text_to_image', 'test');
  assert r->>'code' = 'usage_limit' and (r->>'retry_after')::int between 2000 and 3600, format('31st in an hour: %s', r);

  update public.jobs set created_at = now() - interval '3 hours' where user_id = u;
  insert into public.jobs (user_id, operation, endpoint, cost, status, created_at)
    select u, 'text_to_image', 'test', 1, 'completed', now() - interval '5 hours' from generate_series(1, 70);
  r := public.admit_job(u, 'text_to_image', 'test');
  assert r->>'code' = 'usage_limit' and (r->>'retry_after')::int > 3600, format('101st in a day: %s', r);
  delete from public.jobs where user_id = u;
end $$;

-- 2. Pro gets 20 a minute.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d2';
  r jsonb;
begin
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('otx-abuse-pro', u, 'app.glowlit.pro.monthly', now() + interval '1 month');
  for i in 1..20 loop
    r := public.admit_job(u, 'magic_edit', 'test', p_input_images => 1);
    assert (r->>'ok')::boolean, format('Pro job %s: %s', i, r);
  end loop;
  assert (r->>'credits_remaining')::int = 60, '80 a month, 20 spent';
  assert (select est_cost_cents from public.jobs where id = (r->>'job_id')::uuid) = 7, 'medium quality plus the photo';
  r := public.admit_job(u, 'magic_edit', 'test');
  assert r->>'code' = 'rate_limited', format('21st: %s', r);
  update public.jobs set created_at = now() - interval '2 hours' where user_id = u;
end $$;

-- 3. One network address across users: 120 requests an hour.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d3';
  r jsonb;
begin
  perform public.grant_pack(u, 10, 'tx-abuse-3');
  insert into private.ip_usage (ip_key, hour, requests)
    values (private.keyed_hash('ip', '203.0.113.7'), date_trunc('hour', now()), 120);
  r := public.admit_job(u, 'text_to_image', 'test', p_ip => '203.0.113.7');
  assert r->>'code' = 'usage_limit' and (r->>'retry_after')::int <= 3600, format('121st from one address: %s', r);
  r := public.admit_job(u, 'text_to_image', 'test', p_ip => '198.51.100.9');
  assert (r->>'ok')::boolean, format('another address: %s', r);
  assert not exists (select 1 from private.ip_usage where ip_key like '%203.0%'), 'addresses are stored hashed';
end $$;

-- 4. Breakers: free credits pause first, paid users keep working until the hard cap.
do $$
declare
  free_user uuid := '00000000-0000-0000-0000-0000000000d4';
  pro uuid := '00000000-0000-0000-0000-0000000000d2';
  r jsonb;
  saved private.ai_usage_daily;
begin
  insert into private.ai_usage_daily (day) values ((now() at time zone 'utc')::date) on conflict do nothing;
  select * into saved from private.ai_usage_daily where day = (now() at time zone 'utc')::date;
  update private.ai_usage_daily set free_jobs = 1500 where day = saved.day;

  r := public.admit_job(free_user, 'magic_edit', 'test', p_app_transaction_id => 'atid-d4', p_install_status => 'verified');
  assert r->>'code' = 'ai_paused' and (r->>'status')::int = 503 and (r->>'retry_after')::int > 0, format('free paused: %s', r);
  assert (select daily from private.app_installs where key = private.keyed_hash('app_transaction', 'atid-d4')) = 2,
    'nothing was charged';
  assert not exists (select 1 from public.jobs where user_id = free_user), 'nothing was booked';

  perform public.grant_pack(free_user, 5, 'tx-abuse-4');
  r := public.admit_job(free_user, 'magic_edit', 'test', p_app_transaction_id => 'atid-d4', p_install_status => 'verified');
  assert (r->>'ok')::boolean and not (select free from public.jobs where id = (r->>'job_id')::uuid),
    format('a pack still works, paid from the pack: %s', r);
  assert (select daily from private.app_installs where key = private.keyed_hash('app_transaction', 'atid-d4')) = 2;
  r := public.admit_job(pro, 'magic_edit', 'test');
  assert (r->>'ok')::boolean, format('Pro keeps working: %s', r);

  -- Installs Apple sent no appTransactionId for: a stricter breaker of their own.
  update private.ai_usage_daily set free_jobs = 0, unverified_jobs = 200 where day = saved.day;
  r := public.admit_job('00000000-0000-0000-0000-0000000000d5', 'magic_edit', 'test', p_install_status => 'verified');
  assert r->>'code' = 'ai_paused', format('unverified paused: %s', r);
  update private.ai_usage_daily set unverified_jobs = 0 where day = saved.day;
  r := public.admit_job('00000000-0000-0000-0000-0000000000d5', 'magic_edit', 'test', p_install_status => 'verified');
  assert (r->>'ok')::boolean and (r->>'credits_remaining')::int = 1, format('a per-user allowance: %s', r);
  assert (select unverified_jobs from private.ai_usage_daily where day = saved.day) = 1, 'counted as unverified';
  assert (select kind from private.app_installs i join public.jobs j on j.install_key = i.key
           where j.id = (r->>'job_id')::uuid) = 'unverified';

  -- The hard cap stops everyone.
  update private.ai_usage_daily set total_jobs = 8000 where day = saved.day;
  r := public.admit_job(pro, 'magic_edit', 'test');
  assert r->>'code' = 'ai_paused', format('hard cap: %s', r);
  update private.ai_usage_daily set total_jobs = saved.total_jobs + 3, free_jobs = saved.free_jobs + 1 where day = saved.day;

  -- The owner's switch.
  perform public.ops_pause_ai('free', 1, 'test');
  r := public.admit_job('00000000-0000-0000-0000-0000000000d5', 'magic_edit', 'test', p_install_status => 'verified');
  assert r->>'code' = 'ai_paused', format('free switch: %s', r);
  r := public.admit_job(pro, 'magic_edit', 'test');
  assert (r->>'ok')::boolean, 'paid users keep working while free credits are paused';
  perform public.ops_pause_ai('all', 0.5);
  r := public.admit_job(pro, 'magic_edit', 'test');
  assert r->>'code' = 'ai_paused' and (r->>'retry_after')::int between 1 and 1800, format('all paused: %s', r);
  assert public.ops_resume_ai()->'resumed' @> '["all", "free"]'::jsonb;
  r := public.admit_job('00000000-0000-0000-0000-0000000000d5', 'magic_edit', 'test', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('resumed: %s', r);
end $$;

-- 5. Strikes: three server-side blocks in a day pause cloud AI for 24 hours,
--    for every account on the install, with no charge and no paywall.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d6';
  sibling uuid := '00000000-0000-0000-0000-0000000000d7';
  k text := private.keyed_hash('app_transaction', 'atid-strikes');
  r jsonb;
  state jsonb;
begin
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked' and (r->>'status')::int = 422 and r->>'category' = 'sexual', format('1st: %s', r);
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'appearanceChange');
  assert r->>'code' = 'content_blocked', format('2nd: %s', r);
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'cooldown' and (r->>'status')::int = 429, format('3rd starts a cool-down: %s', r);
  assert (r->>'retry_after')::int between 86000 and 86400, format('for 24 hours: %s', r);
  assert not exists (select 1 from public.jobs where user_id = u and (cost > 0 or status <> 'failed')),
    'a blocked prompt is booked as a failed attempt, never charged';

  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified');
  assert r->>'code' = 'cooldown', format('resting: %s', r);
  state := public.wallet_state(u, 'atid-strikes', 'verified', 'Sandbox');
  assert state->>'ai_status' = 'cooldown' and state->>'cooldown_until' is not null, format('the app knows: %s', state);
  assert (state->>'credits_remaining')::int = 2, 'her free credits wait for her';
  r := public.admit_job(sibling, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified');
  assert r->>'code' = 'cooldown', format('a new anonymous account on the same install rests too: %s', r);
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'cooldown', 'no strikes pile up while resting';
  assert (select count(*) from private.cooldowns where install_key = k) = 1, 'one cool-down';

  assert (public.ops_unblock(p_install => k)->>'cooldowns_lifted')::int = 1, 'the owner can lift it';
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('back to normal: %s', r);
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', 'a lifted cool-down starts a clean slate';
end $$;

-- 6. Repeated cool-downs block the install until the owner lifts it.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d6';
  sibling uuid := '00000000-0000-0000-0000-0000000000d7';
  k text := private.keyed_hash('app_transaction', 'atid-strikes');
  r jsonb;
begin
  delete from private.cooldowns where install_key = k;
  insert into private.cooldowns (user_id, install_key, starts_at, ends_at) values
    (u, k, now() - interval '12 days', now() - interval '11 days'),
    (u, k, now() - interval '5 days', now() - interval '4 days');
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified',
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'install_blocked' and (r->>'status')::int = 403, format('third cool-down in 30 days: %s', r);
  r := public.admit_job(sibling, 'text_to_image', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified');
  assert r->>'code' = 'install_blocked', 'every account on the install';
  assert public.wallet_state(sibling, 'atid-strikes', 'verified', 'Sandbox')->>'ai_status' = 'blocked';
  assert (select count(*) from public.ops_strikes(7) s where s.install_key = k and s.blocked) = 1, 'the owner sees it';
  assert (public.ops_unblock(p_install => k)->>'blocks_lifted')::int = 1;
  r := public.admit_job(sibling, 'text_to_image', 'test', p_app_transaction_id => 'atid-strikes', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('lifted: %s', r);
end $$;

-- 7. A flagged output fails, is refunded and counts as a strike.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d8';
  r jsonb;
begin
  perform public.grant_pack(u, 3, 'tx-abuse-7');
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-d8', p_install_status => 'verified');
  update public.jobs set status = 'processing' where id = (r->>'job_id')::uuid;
  r := public.flag_job((r->>'job_id')::uuid, 'content_blocked', 'This result was blocked by our safety filters.', 'output');
  assert r->>'state' = 'strike', format('a strike: %s', r);
  assert (select status from public.jobs where user_id = u) = 'failed';
  assert (public.wallet_state(u, 'atid-d8', 'verified', 'Sandbox')->>'credits_remaining')::int = 5, 'refunded';
  assert (select count(*) from private.strikes where user_id = u and source = 'output') = 1;
end $$;

-- 8. Likeness Lock: one free retry per recent result, three a day.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d9';
  originals uuid[];
  j uuid;
  r jsonb;
begin
  perform public.grant_pack(u, 10, 'tx-abuse-8');
  for i in 1..5 loop
    r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-d9', p_install_status => 'verified');
    originals := originals || (r->>'job_id')::uuid;
  end loop;
  update public.jobs set status = 'completed' where id = any (originals);
  assert (select free from public.jobs where id = originals[1]) and not (select free from public.jobs where id = originals[3]);
  -- Out of the per-minute window (rate limits come first), still within the 15 minutes.
  update public.jobs set created_at = now() - interval '2 minutes' where user_id = u;

  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[1], p_app_transaction_id => 'atid-d9',
                        p_install_status => 'verified');
  assert (r->>'ok')::boolean and (select cost from public.jobs where id = (r->>'job_id')::uuid) = 0, format('free retry: %s', r);
  assert (select free from public.jobs where id = (r->>'job_id')::uuid), 'a retry of a free job counts as free';
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[1]);
  assert r->>'code' = 'retry_unavailable', 'once per result';
  r := public.admit_job(u, 'text_to_image', 'test', p_retry_of => originals[2]);
  assert r->>'code' = 'retry_unavailable', 'same operation only';
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[2]);
  assert (r->>'ok')::boolean;
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[3]);
  assert (r->>'ok')::boolean;
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[4]);
  assert r->>'code' = 'retry_limit' and (r->>'status')::int = 409, format('the 4th free retry today: %s', r);
  assert not (select retried from public.jobs where id = originals[4]), 'a refused retry stays available';
  update public.jobs set created_at = now() - interval '20 minutes' where id = originals[5];
  delete from public.jobs where user_id = u and retry_of is not null;
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[5]);
  assert r->>'code' = 'retry_unavailable', 'only within 15 minutes';
end $$;

-- 9. Reports: ten a day, linked only to her own jobs.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d8';
  theirs uuid := (select id from public.jobs where user_id = '00000000-0000-0000-0000-0000000000d9' limit 1);
  r jsonb;
begin
  r := public.file_report(u, 'other', theirs, '  not mine  ');
  assert (r->>'ok')::boolean;
  assert (select job_id from public.reports where user_id = u) is null, 'someone else''s job is never linked';
  assert (select details from public.reports where user_id = u) = 'not mine', 'details trimmed';
  for i in 2..10 loop
    r := public.file_report(u, 'mismatch');
    assert (r->>'ok')::boolean, format('report %s: %s', i, r);
  end loop;
  r := public.file_report(u, 'mismatch');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('11th: %s', r);
  assert (select count(*) from public.reports where user_id = u) = 10;
end $$;

-- 10. Owner tools.
do $$
declare
  summary jsonb;
  j uuid := (select id from public.jobs where user_id = '00000000-0000-0000-0000-0000000000d8' limit 1);
  r jsonb;
begin
  summary := public.ops_daily_summary();
  assert summary ? 'jobs' and summary ? 'estimated_cost_usd' and summary ? 'breakers' and summary ? 'safety', format('%s', summary);
  assert (summary->'jobs'->>'total')::int > 0 and (summary->'safety'->>'strikes')::int >= 6, format('%s', summary);
  assert (summary->'estimated_cost_usd'->>'admitted_upper_bound')::numeric > 0;
  assert (select count(*) from public.ops_reports()) >= 10;
  perform public.ops_set_report_status((select report_id from public.ops_reports() limit 1), 'reviewed');
  assert (select count(*) from public.ops_reports('reviewed')) = 1;
  r := public.ops_block(p_job => j, p_reason => 'report review');
  assert (r->>'new_install_block')::boolean, format('%s', r);
  assert public.admit_job('00000000-0000-0000-0000-0000000000d8', 'magic_edit', 'test')->>'code' = 'install_blocked',
    'the user behind the job is blocked too';
  perform public.ops_unblock(p_install => r->>'install_key', p_user => '00000000-0000-0000-0000-0000000000d8');
end $$;

-- 11. Deleting the account keeps only the hashed install's counts.
do $$
declare
  k text := private.keyed_hash('app_transaction', 'atid-strikes');
begin
  delete from auth.users where id = '00000000-0000-0000-0000-0000000000d6';
  assert (select count(*) from private.strikes where user_id = '00000000-0000-0000-0000-0000000000d6') = 0,
    'nothing points at the deleted user';
  assert (select count(*) from private.strikes where install_key = k) > 0, 'the install''s strikes stay, to prevent abuse';
  assert exists (select 1 from private.app_installs where key = k);
end $$;

-- 12. Retention.
do $$
declare
  old_key text := private.keyed_hash('app_transaction', 'atid-old');
  blocked_key text := private.keyed_hash('app_transaction', 'atid-old-blocked');
begin
  insert into private.app_installs (key, kind, last_seen_at) values
    (old_key, 'app_store', now() - interval '31 days'),
    (blocked_key, 'app_store', now() - interval '31 days');
  insert into private.blocks (install_key, reason) values (blocked_key, 'test');
  insert into private.strikes (install_key, source, created_at) values (old_key, 'prompt', now() - interval '31 days');
  insert into private.ip_usage (ip_key, hour, requests) values ('old-ip', now() - interval '2 days', 3);
  insert into private.blocks (install_key, reason, created_at) values ('ancient', 'test', now() - interval '13 months');
  perform public.sweep_jobs();
  assert not exists (select 1 from private.app_installs where key = old_key), 'unused installs go after 30 days';
  assert exists (select 1 from private.app_installs where key = blocked_key), 'unless blocked';
  assert not exists (select 1 from private.strikes where install_key = old_key), 'strikes go after 30 days';
  assert not exists (select 1 from private.ip_usage where ip_key = 'old-ip'), 'address counts go after a day';
  assert not exists (select 1 from private.blocks where install_key = 'ancient'), 'blocks end after 12 months';
  delete from private.blocks where install_key = blocked_key;
end $$;

-- 13. A policy block is a strike only past the rate limits, and it counts toward
--     them: a refused request writes nothing, a blocked one uses up its place.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d10';
  r jsonb;
  strikes int;
begin
  perform public.grant_pack(u, 20, 'tx-abuse-10');
  for i in 1..5 loop
    r := public.admit_job(u, 'text_to_image', 'test');
    assert (r->>'ok')::boolean, format('job %s: %s', i, r);
  end loop;
  r := public.admit_job(u, 'text_to_image', 'test', p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('the sixth request, blocked: %s', r);
  select count(*) into strikes from private.strikes where user_id = u;
  assert strikes = 1, format('one strike: %s', strikes);
  r := public.admit_job(u, 'text_to_image', 'test', p_blocked_category => 'sexual');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('a blocked request past the minute: %s', r);
  assert (select count(*) from private.strikes where user_id = u) = strikes, 'a refused request writes no strike';
  r := public.admit_job(u, 'text_to_image', 'test');
  assert r->>'code' = 'rate_limited', format('the blocked request used up the minute: %s', r);
  assert (select count(*) from public.jobs where user_id = u) = 6, 'the blocked attempt is booked, the refused ones are not';
  update public.jobs set created_at = now() - interval '2 minutes' where user_id = u;
  r := public.admit_job(u, 'text_to_image', 'test');
  assert (r->>'ok')::boolean, format('the minute is free again: %s', r);
end $$;

-- 14. The owner's pause stops policy-blocked requests too, and writes nothing.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d11';
  r jsonb;
begin
  perform public.grant_pack(u, 5, 'tx-abuse-11');
  perform public.ops_pause_ai('all', 0.5, 'test');
  r := public.admit_job(u, 'magic_edit', 'test', p_blocked_category => 'sexual');
  assert r->>'code' = 'ai_paused' and (r->>'status')::int = 503, format('paused, prompt blocked: %s', r);
  assert not exists (select 1 from private.strikes where user_id = u), 'no strike while paused';
  assert not exists (select 1 from public.jobs where user_id = u), 'nothing booked while paused';
  assert public.ops_resume_ai('all')->'resumed' = '["all"]'::jsonb, 'resumed';
  r := public.admit_job(u, 'magic_edit', 'test', p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('after the pause the policy applies again: %s', r);
end $$;

-- 15. No verified App Store install: the address is the install. Fresh anonymous
--     accounts on one address share its strikes, so rotating accounts gains nothing.
do $$
declare
  ip text := '192.0.2.44';
  k text := private.keyed_hash('ip', ip);
  r jsonb;
begin
  r := public.admit_job('00000000-0000-0000-0000-000000000d12', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('1st: %s', r);
  r := public.admit_job('00000000-0000-0000-0000-000000000d13', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('2nd, another new account: %s', r);
  r := public.admit_job('00000000-0000-0000-0000-000000000d14', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'cooldown' and (r->>'status')::int = 429, format('3rd from the address: %s', r);
  assert (r->>'retry_after')::int between 86000 and 86400, format('for 24 hours: %s', r);
  assert (select count(*) from private.cooldowns where install_key = k) = 1, 'the cool-down is on the address';
  assert (select count(*) from private.strikes where install_key = k) = 3, 'the strikes are on the address';
  assert (select count(*) from public.jobs where install_key = k) = 3, 'the attempts carry the address key';
  r := public.admit_job('00000000-0000-0000-0000-000000000d15', 'magic_edit', 'test', p_ip => ip);
  assert r->>'code' = 'cooldown', format('a fourth account on the address rests too: %s', r);
  r := public.admit_job('00000000-0000-0000-0000-000000000d15', 'magic_edit', 'test', p_ip => '192.0.2.45');
  assert r->>'code' is distinct from 'cooldown', format('another address is not affected: %s', r);
end $$;

-- 16. A block on an address is not tied to the account that tripped it, so
--     deleting that account does not lift it (the data is hashed; the account is not).
do $$
declare
  ip text := '192.0.2.60';
  k text := private.keyed_hash('ip', ip);
  r jsonb;
begin
  insert into private.cooldowns (user_id, install_key, starts_at, ends_at) values
    ('00000000-0000-0000-0000-000000000d16', k, now() - interval '12 days', now() - interval '11 days'),
    ('00000000-0000-0000-0000-000000000d16', k, now() - interval '5 days', now() - interval '4 days');
  r := public.admit_job('00000000-0000-0000-0000-000000000d16', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  r := public.admit_job('00000000-0000-0000-0000-000000000d17', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  r := public.admit_job('00000000-0000-0000-0000-000000000d18', 'magic_edit', 'test', p_ip => ip,
                        p_blocked_category => 'sexual');
  assert r->>'code' = 'install_blocked' and (r->>'status')::int = 403, format('third cool-down in 30 days: %s', r);
  assert not exists (select 1 from private.blocks where user_id = '00000000-0000-0000-0000-000000000d18'),
    'the block is on the address, not the account';
  assert (select count(*) from private.blocks where install_key = k and lifted_at is null) = 1, 'one block on the address';
  delete from auth.users where id = '00000000-0000-0000-0000-000000000d18';
  r := public.admit_job('00000000-0000-0000-0000-000000000d19', 'magic_edit', 'test', p_ip => ip);
  assert r->>'code' = 'install_blocked', format('a new account on the address, after the deletion: %s', r);
end $$;

-- 17. Lifting a block starts the cool-down history over. Each step is its own
--     transaction, so the strikes and the lift get different timestamps.
do $$
declare
  k text := private.keyed_hash('app_transaction', 'atid-lift');
  u uuid := '00000000-0000-0000-0000-000000000d20';
  r jsonb;
begin
  insert into private.cooldowns (user_id, install_key, starts_at, ends_at) values
    (u, k, now() - interval '12 days', now() - interval '11 days'),
    (u, k, now() - interval '5 days', now() - interval '4 days');
  for i in 1..2 loop
    r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-lift',
                          p_install_status => 'verified', p_blocked_category => 'sexual');
    assert r->>'code' = 'content_blocked', format('strike %s: %s', i, r);
  end loop;
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-lift',
                        p_install_status => 'verified', p_blocked_category => 'sexual');
  assert r->>'code' = 'install_blocked', format('third cool-down in 30 days: %s', r);
end $$;

do $$
declare
  k text := private.keyed_hash('app_transaction', 'atid-lift');
  u uuid := '00000000-0000-0000-0000-000000000d20';
begin
  assert (public.ops_unblock(p_install => k)->>'blocks_lifted')::int = 1, 'lifted';
  update public.jobs set created_at = now() - interval '2 minutes' where user_id = u;
end $$;

do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d20';
  r jsonb;
begin
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-lift',
                        p_install_status => 'verified', p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('one new blocked prompt does not block again: %s', r);
end $$;

do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d20';
  r jsonb;
begin
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-lift',
                        p_install_status => 'verified', p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('the second: %s', r);
end $$;

do $$
declare
  k text := private.keyed_hash('app_transaction', 'atid-lift');
  u uuid := '00000000-0000-0000-0000-000000000d20';
  r jsonb;
begin
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-lift',
                        p_install_status => 'verified', p_blocked_category => 'sexual');
  assert r->>'code' = 'cooldown', format('the third starts a new cool-down, not a block: %s', r);
  assert not exists (select 1 from private.blocks where install_key = k and lifted_at is null), 'no block again';
end $$;

-- 18. Clients can call none of it; the keep-alive stays open to anon on purpose.
do $$
begin
  assert not has_function_privilege('anon', 'public.admit_job(uuid, text, text, text, int, int, uuid, text, text, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.admit_job(uuid, text, text, text, int, int, uuid, text, text, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.flag_job(uuid, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.file_report(uuid, text, uuid, text)', 'execute');
  assert not has_function_privilege('anon', 'public.ops_daily_summary(date)', 'execute');
  assert not has_function_privilege('authenticated', 'public.ops_block(text, uuid, uuid, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.ops_pause_ai(text, numeric, text)', 'execute');
  assert not has_function_privilege('anon', 'public.ops_unblock(text, uuid)', 'execute');
  assert not has_function_privilege('authenticated', 'public.ops_unblock(text, uuid)', 'execute');
  assert not has_function_privilege('anon', 'public.ops_strikes(int)', 'execute');
  assert not has_function_privilege('authenticated', 'public.ops_strikes(int)', 'execute');
  assert has_function_privilege('service_role', 'public.ops_daily_summary(date)', 'execute');
  assert has_function_privilege('anon', 'public.keepalive()', 'execute'), 'the documented exception';
end $$;

-- 19. Likeness Lock: a retry that was refunded (it failed, timed out or she
--     cancelled it) gives its daily slot back. Retries she got, or is still
--     waiting for, use the three.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d21';
  originals uuid[];
  r jsonb;
begin
  insert into auth.users (id) values (u);
  -- Pro allows 20 jobs a minute, so the per-minute limit stays out of the way.
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('otx-abuse-retries', u, 'app.glowlit.pro.monthly', now() + interval '1 month');
  for i in 1..5 loop
    r := public.admit_job(u, 'magic_edit', 'test', p_input_images => 1);
    assert (r->>'ok')::boolean, format('original %s: %s', i, r);
    originals := originals || (r->>'job_id')::uuid;
  end loop;
  update public.jobs set status = 'completed', delivered_at = now() where id = any (originals);

  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[1]);
  assert (r->>'ok')::boolean, format('retry 1: %s', r);
  assert public.fail_job((r->>'job_id')::uuid, 'provider_failed', 'This creation failed.'), 'the provider failed';
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[2]);
  assert (r->>'ok')::boolean, format('retry 2: %s', r);
  assert public.fail_job((r->>'job_id')::uuid, 'timeout', 'This took too long.'), 'it timed out';
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[3]);
  assert (r->>'ok')::boolean, format('retry 3: %s', r);
  assert public.cancel_job((r->>'job_id')::uuid, u, true)->>'status' = 'cancelled', 'she cancelled it';

  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[4]);
  assert (r->>'ok')::boolean, format('three refunded retries leave today''s three free: %s', r);
  -- A failed retry also gave its result's retry back (fail_job).
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[1]);
  assert (r->>'ok')::boolean, format('the failed one again: %s', r);
  update public.jobs set status = 'completed', delivered_at = now() where id = (r->>'job_id')::uuid;
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[2]);
  assert (r->>'ok')::boolean, format('the timed-out one again: %s', r);
  r := public.admit_job(u, 'magic_edit', 'test', p_retry_of => originals[5]);
  assert r->>'code' = 'retry_limit', format('two running and one delivered use the three: %s', r);
  assert not (select retried from public.jobs where id = originals[5]), 'a refused retry stays available';
end $$;

-- 20. A job she cancelled is no strike, even when its result comes back flagged.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000d22';
  j uuid;
  r jsonb;
begin
  insert into auth.users (id) values (u);
  perform public.grant_pack(u, 3, 'tx-abuse-20');
  r := public.admit_job(u, 'magic_edit', 'test', p_app_transaction_id => 'atid-d22', p_install_status => 'verified');
  j := (r->>'job_id')::uuid;
  update public.jobs set status = 'processing' where id = j;
  assert public.cancel_job(j, u, true)->>'status' = 'cancelled', 'she cancelled it';
  -- The provider answers after the cancel, and the output check flags it.
  r := public.flag_job(j, 'content_blocked', 'This result was blocked by our safety filters.', 'output');
  assert r is null, format('no strike: %s', r);
  assert not exists (select 1 from private.strikes where user_id = u or job_id = j), 'nothing recorded';
  assert (select status from public.jobs where id = j) = 'cancelled', 'still cancelled';
  assert (public.wallet_state(u, 'atid-d22', 'verified', 'Sandbox')->>'credits_remaining')::int = 5, 'refunded once';
end $$;

-- 21. The balance shows a cool-down or block kept on the address (no verified
--     install), as admit_job sees it.
do $$
declare
  ip text := '192.0.2.80';
  k text := private.keyed_hash('ip', ip);
  u uuid := '00000000-0000-0000-0000-000000000d23';
  sibling uuid := '00000000-0000-0000-0000-000000000d24';
  state jsonb;
begin
  insert into auth.users (id) values (u), (sibling);
  insert into private.cooldowns (install_key, ends_at) values (k, now() + interval '20 hours');
  state := public.wallet_state(u, null, 'missing', null, ip);
  assert state->>'ai_status' = 'cooldown' and state->>'cooldown_until' is not null, format('address cool-down: %s', state);
  assert (state->>'cooldown_seconds')::int between 71900 and 72000, format('20 hours: %s', state);
  assert public.admit_job(u, 'magic_edit', 'test', p_ip => ip)->>'code' = 'cooldown', 'the same answer as a job';
  assert public.wallet_state(u, null, 'missing', null, '192.0.2.81')->>'ai_status' = 'ok', 'another address is not affected';
  assert public.wallet_state(u)->>'ai_status' = 'ok', 'the call without an address still works';
  -- A verified install is judged by the install, not the address (admit_job does the same).
  assert public.wallet_state(u, 'atid-d23', 'verified', 'Sandbox', ip)->>'ai_status' = 'ok', 'a verified install';

  insert into private.blocks (install_key, reason) values (k, 'test');
  state := public.wallet_state(sibling, null, 'invalid', null, ip);
  assert state->>'ai_status' = 'blocked', format('an address block, for every account on it: %s', state);
  delete from private.blocks where install_key = k;
end $$;

select 'all abuse control tests passed' as result;
