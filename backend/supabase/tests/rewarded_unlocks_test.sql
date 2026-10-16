-- Pro tries from rewarded ads (20261101000000): one try of a Pro look or style
-- for a watched ad. Run with backend/scripts/test-db.sh. Each block raises
-- (ASSERT) on failure; psql stops on the first error.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000a7e01'),  -- she: a try, admissions and refunds
  ('00000000-0000-0000-0000-0000000a7e02'),  -- another account on her App Store install
  ('00000000-0000-0000-0000-0000000a7e03'),  -- refusals before an ad
  ('00000000-0000-0000-0000-0000000a7e04'),  -- Pro
  ('00000000-0000-0000-0000-0000000a7e05'),  -- a free retry
  ('00000000-0000-0000-0000-0000000a7e06'),  -- the other gates
  ('00000000-0000-0000-0000-0000000a7e07'),  -- Sign in with Apple: the anonymous account
  ('00000000-0000-0000-0000-0000000a7e08');  -- Sign in with Apple: the account it joins

-- Today's breaker counts as the earlier suites left them, put back at the end,
-- so this suite's jobs trip no breaker and later suites see what they'd see.
create temp table try_saved_usage as
  select * from private.ai_usage_daily where day = (now() at time zone 'utc')::date;
do $$
begin
  perform public.ops_resume_ai();
  insert into private.ai_usage_daily (day) values ((now() at time zone 'utc')::date) on conflict (day) do nothing;
  update private.ai_usage_daily set total_jobs = 0, free_jobs = 0, unverified_jobs = 0
   where day = (now() at time zone 'utc')::date;
end $$;

-- 1. The numbers, and only the server can use any of it.
do $$
declare
  pol record;
  fn text;
begin
  select * into pol from public.ad_reward_policy();
  assert (pol.daily_cap, pol.credits, pol.token_ttl, pol.unlock_daily_cap, pol.unlock_ttl)
         = (2, 1, interval '30 minutes', 1, interval '30 minutes'), format('the policy: %s', row_to_json(pol));
  foreach fn in array array[
    'public.ad_reward_policy()',
    'public.ad_rewards_used_today(uuid, text, text)',
    'public.issue_ad_unlock_token(uuid, boolean, text, text, text, text, text)',
    'public.redeem_ad_reward(text, uuid, text, int, text)',
    'public.ad_reward_status(uuid, uuid)',
    'public.release_ad_reward_token(uuid, uuid)',
    'public.ad_reward_overview(uuid, boolean, text, text, text)',
    'public.ad_unlock_available(uuid, text, text, uuid)',
    'public.admit_unlocked_job(uuid, text, text, text, text, text, int, int, uuid, text, text, text, text, text)',
    'public.release_credits(uuid)',
    'public.merge_accounts(uuid, uuid)',
    'public.sweep_ad_rewards()'
  ] loop
    assert not has_function_privilege('anon', fn, 'execute'), format('anon can run %s', fn);
    assert not has_function_privilege('authenticated', fn, 'execute'), format('clients can run %s', fn);
    assert has_function_privilege('service_role', fn, 'execute'), format('the Edge Functions can''t run %s', fn);
    assert (select proconfig::text from pg_proc where oid = fn::regprocedure) like '%search_path=%',
      format('%s pins its search_path', fn);
  end loop;
  assert (select prosecdef from pg_proc where oid = 'public.admit_unlocked_job(uuid, text, text, text, text, text, int, int, uuid, text, text, text, text, text)'::regprocedure),
    'admission runs as its owner';
  assert (select relrowsecurity from pg_class where oid = 'private.ad_unlocks'::regclass), 'RLS is on';
  assert not exists (select 1 from pg_policies where schemaname = 'private' and tablename = 'ad_unlocks'), 'no policies';
  assert not has_table_privilege('authenticated', 'private.ad_unlocks', 'select'), 'clients read no tries';
  assert not has_table_privilege('anon', 'private.ad_unlocks', 'insert'), 'nor make one';
end $$;

-- 2. No token for a try without a verified install, for Pro, while AI rests
--    for everyone, without a credit to spend on it, or while she rests. The
--    credit ads' cap is not the tries' cap.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000a7e03';
  k text := private.keyed_hash('app_transaction', 'atid-try-3');
  reason text;
  token uuid;
begin
  perform public.wallet_state(u, 'atid-try-3', 'verified', 'Sandbox');

  begin
    perform public.issue_ad_unlock_token(u, false, 'sticker', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_BAD_UNLOCK%', format('only a look or a style, got %s', reason);

  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, false, 'template', 'doll-box');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NO_INSTALL%', format('no verified install, no ad, got %s', reason);

  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, true, 'template', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NOT_ELIGIBLE%', format('Pro has every look already, got %s', reason);

  perform public.ops_pause_ai('all', 1, 'rewarded unlocks test');
  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, false, 'template', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_AI_PAUSED%', format('a try that couldn''t start a job isn''t offered, got %s', reason);
  assert not (public.ad_reward_overview(u, false, 'atid-try-3', 'verified', 'Sandbox')->'unlock'->>'eligible')::boolean,
    'none on offer while paused';
  perform public.ops_resume_ai();

  update private.ai_usage_daily set total_jobs = 400 where day = (now() at time zone 'utc')::date;
  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, false, 'template', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_AI_PAUSED%', format('nor after the day''s hard breaker, got %s', reason);
  update private.ai_usage_daily set total_jobs = 0 where day = (now() at time zone 'utc')::date;

  update private.app_installs set daily = 0 where key = k;
  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, false, 'template', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NO_CREDITS%', format('a try costs a credit, so none without one, got %s', reason);
  assert not (public.ad_reward_overview(u, false, 'atid-try-3', 'verified', 'Sandbox')->'unlock'->>'eligible')::boolean,
    'none on offer without a credit';
  update private.app_installs set daily = 2 where key = k;

  insert into private.cooldowns (user_id, install_key, ends_at) values (u, k, now() + interval '1 hour');
  reason := null;
  begin
    perform public.issue_ad_unlock_token(u, false, 'template', 'doll-box', 'atid-try-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NOT_ELIGIBLE%', format('resting, got %s', reason);
  delete from private.cooldowns where user_id = u;
  assert not exists (select 1 from public.ad_reward_tokens where user_id = u), 'no token so far';

  -- Both credit ads of the day used: a try is still on offer, under its own cap.
  insert into public.ad_rewards (transaction_id, user_id, token_id, ad_unit, credits, status, reward_day, install_key)
    select 'tx-try-credit-' || n, u, gen_random_uuid(), '1406702504', 1, 'granted', (now() at time zone 'utc')::date, k
      from generate_series(1, 2) n;
  assert (public.ad_reward_overview(u, false, 'atid-try-3', 'verified', 'Sandbox')->>'remaining_today')::int = 0,
    'no credit ad left today';
  assert (public.ad_reward_overview(u, false, 'atid-try-3', 'verified', 'Sandbox')->'unlock'->>'eligible')::boolean,
    'a try is still on offer';
  select reward_token into token
    from public.issue_ad_unlock_token(u, false, 'style', 'fantasy', 'atid-try-3', 'verified', 'Sandbox');
  assert (select released from public.release_ad_reward_token(u, token)), 'and closing it early gives it back';
end $$;

-- 3. One try a day per user and per install, counted apart from the credit
--    ads, with its token naming its look.
do $$
declare
  she uuid := '00000000-0000-0000-0000-0000000a7e01';
  sibling uuid := '00000000-0000-0000-0000-0000000a7e02';
  k text := private.keyed_hash('app_transaction', 'atid-try-1');
  t record;
  r record;
  credit uuid;
  left_today int;
  reason text;
begin
  perform public.wallet_state(she, 'atid-try-1', 'verified', 'Sandbox');
  assert public.ad_reward_overview(she, false, 'atid-try-1', 'verified', 'Sandbox')->'unlock'
         = '{"remaining_today": 1, "daily_cap": 1, "eligible": true, "active": []}'::jsonb, 'a try on offer';
  select * into t
    from public.issue_ad_unlock_token(she, false, 'template', 'doll-box', 'atid-try-1', 'verified', 'Sandbox');
  assert t.remaining_today = 0, 'one try a day';
  assert t.valid_until between now() + interval '29 minutes' and now() + interval '31 minutes', 'a 30-minute token';
  assert (select (kind, unlock_type, unlock_id, install_key) = ('unlock', 'template', 'doll-box', k)
            from public.ad_reward_tokens where id = t.reward_token), 'the token names its look';
  assert public.ad_rewards_used_today(she, k, 'unlock') = 1, 'a waiting token counts toward the tries';
  assert public.ad_rewards_used_today(she, k) = 0, 'not toward the credit ads';
  select * into r from public.ad_reward_status(she, t.reward_token);
  assert (r.outcome, r.reward_kind, r.unlock_type, r.unlock_id, r.remaining_today)
         = ('pending', 'unlock', 'template', 'doll-box', 0) and r.unlock_expires_at is null,
    format('pending: %s', row_to_json(r));

  begin
    perform public.issue_ad_unlock_token(she, false, 'style', 'fantasy', 'atid-try-1', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_DAILY_CAP%', format('one a day, got %s', reason);
  reason := null;
  begin
    perform public.issue_ad_unlock_token(sibling, false, 'template', 'doll-box', 'atid-try-1', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_DAILY_CAP%', format('one a day per install, whatever the account, got %s', reason);

  -- Out of credits, her two credit ads are still there.
  update private.app_installs set daily = 0 where key = k;
  select reward_token, remaining_today into credit, left_today
    from public.issue_ad_reward_token(she, false, 'atid-try-1', 'verified', 'Sandbox');
  assert left_today = 1, 'the first credit ad of two';
  assert public.ad_rewards_used_today(she, k, 'unlock') = 1, 'the try''s place is unchanged';
  select * into r from public.release_ad_reward_token(she, credit);
  assert r.released and r.reward_kind = 'credit' and r.remaining_today = 2, format('credit released: %s', row_to_json(r));
  update private.app_installs set daily = 2 where key = k;

  -- The ad closed early: the try's place comes back.
  select * into r from public.release_ad_reward_token(she, t.reward_token);
  assert r.released and r.reward_kind = 'unlock' and r.remaining_today = 1, format('try released: %s', row_to_json(r));
  assert public.ad_rewards_used_today(she, k, 'unlock') = 0, 'its place is free again';

  -- The token AdMob confirms in block 4.
  perform public.issue_ad_unlock_token(she, false, 'template', 'doll-box', 'atid-try-1', 'verified', 'Sandbox');
end $$;

-- 4. AdMob's verified callback grants the try, once: no credit, 30 minutes.
do $$
declare
  she uuid := '00000000-0000-0000-0000-0000000a7e01';
  k text := private.keyed_hash('app_transaction', 'atid-try-1');
  token uuid;
  balance int;
  r record;
  u private.ad_unlocks;
begin
  select id into token from public.ad_reward_tokens where user_id = she and kind = 'unlock' and redeemed_at is null;
  balance := private.balance_of(she, k);
  select * into r from public.redeem_ad_reward('tx-try-1', token, '1406702504', 1, 'credit');
  assert r.outcome = 'granted' and r.credits_remaining = balance, format('a try, not a credit: %s', row_to_json(r));
  assert (select (kind, credits, status, install_key) = ('unlock', 0, 'granted', k)
            from public.ad_rewards where transaction_id = 'tx-try-1'), 'recorded as a try';
  assert not exists (select 1 from public.credit_ledger where source_ref = 'admob:tx-try-1'), 'no credit in the ledger';
  assert private.daily_ceiling(k) = 2, 'nor above the day''s free credits';
  select * into u from private.ad_unlocks where transaction_id = 'tx-try-1';
  assert (u.user_id, u.unlock_type, u.unlock_id) = (she, 'template', 'doll-box') and u.job_id is null and u.used_at is null,
    format('one unused try of that look: %s', row_to_json(u));
  assert u.expires_at between now() + interval '29 minutes' and now() + interval '31 minutes', '30 minutes from the grant';

  select * into r from public.ad_reward_status(she, token);
  assert (r.outcome, r.reward_kind, r.unlock_type, r.unlock_id, r.unlock_expires_at, r.remaining_today)
         = ('granted', 'unlock', 'template', 'doll-box', u.expires_at, 0), format('the app sees it: %s', row_to_json(r));
  assert public.ad_reward_overview(she, false, 'atid-try-1', 'verified', 'Sandbox')->'unlock'->'active'
         = jsonb_build_array(jsonb_build_object('template_id', 'doll-box', 'expires_at', u.expires_at)), 'and holds it';

  assert (select outcome from public.redeem_ad_reward('tx-try-1', token, '1406702504', 1, 'credit')) = 'duplicate',
    'AdMob''s retry';
  assert (select outcome from public.redeem_ad_reward('tx-try-1b', token, '1406702504', 1, 'credit')) = 'used',
    'a token pays once';
  assert (select count(*) from private.ad_unlocks where user_id = she) = 1, 'exactly one try';
end $$;

-- 5. The cap holds when AdMob calls back too, and a late callback pays nothing.
do $$
declare
  sibling uuid := '00000000-0000-0000-0000-0000000a7e02';
  k text := private.keyed_hash('app_transaction', 'atid-try-1');
  extra uuid;
  late uuid;
  r record;
begin
  -- A token for another account on her install, as if issued before her try was paid.
  insert into public.ad_reward_tokens (user_id, install_key, expires_at, kind, unlock_type, unlock_id)
    values (sibling, k, now() + interval '10 minutes', 'unlock', 'style', 'fantasy')
    returning id into extra;
  select * into r from public.redeem_ad_reward('tx-try-2', extra, '1406702504', 1, 'credit');
  assert r.outcome = 'capped', format('a second try for the install today: %s', row_to_json(r));
  assert not exists (select 1 from private.ad_unlocks where transaction_id = 'tx-try-2'), 'no try';

  insert into public.ad_reward_tokens (user_id, install_key, expires_at, kind, unlock_type, unlock_id)
    values (sibling, private.keyed_hash('app_transaction', 'atid-try-2'), now() - interval '1 minute',
            'unlock', 'template', 'figurine')
    returning id into late;
  select * into r from public.redeem_ad_reward('tx-try-3', late, '1406702504', 1, 'credit');
  assert r.outcome = 'expired', format('late: %s', row_to_json(r));
  assert not exists (select 1 from private.ad_unlocks where transaction_id = 'tx-try-3'), 'no try';

  begin
    insert into public.ad_reward_tokens (user_id, expires_at, kind) values (sibling, now(), 'unlock');
    assert false, 'a try''s token must name its look';
  exception when check_violation then
    null;
  end;
end $$;

-- 6. Admission: without a try of exactly that id, 'pro_required' and nothing
--    booked; with one, admitted for a credit like any look, the try spent.
do $$
declare
  she uuid := '00000000-0000-0000-0000-0000000a7e01';
  sibling uuid := '00000000-0000-0000-0000-0000000a7e02';
  k text := private.keyed_hash('app_transaction', 'atid-try-1');
  r jsonb;
  j uuid;
  daily_before int;
  jobs_before int;
begin
  assert public.ad_unlock_available(she, 'template', 'doll-box'), 'she holds a try of that look';
  assert not public.ad_unlock_available(she, 'template', 'figurine'), 'not of another look';
  assert not public.ad_unlock_available(she, 'style', 'doll-box'), 'nor of a style by that name';
  assert not public.ad_unlock_available(sibling, 'template', 'doll-box'), 'nor for another account';

  daily_before := (select daily from private.app_installs where key = k);
  jobs_before := (select count(*) from public.jobs where user_id in (she, sibling));
  r := public.admit_unlocked_job(she, 'template', 'figurine', 'restyle', 'test', p_template_id => 'figurine',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert r->>'code' = 'pro_required' and (r->>'status')::int = 402, format('wrong id: %s', r);
  r := public.admit_unlocked_job(sibling, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert r->>'code' = 'pro_required', format('her try is hers: %s', r);
  assert (select count(*) from public.jobs where user_id in (she, sibling)) = jobs_before, 'nothing booked';
  assert (select daily from private.app_installs where key = k) = daily_before, 'nothing charged';

  r := public.admit_unlocked_job(she, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('admitted: %s', r);
  j := (r->>'job_id')::uuid;
  assert (select job_id = j and used_at is not null from private.ad_unlocks where transaction_id = 'tx-try-1'),
    'spent on that job, in the same transaction';
  assert (select cost from public.jobs where id = j) = 1, 'a look costs a credit';
  assert (select daily from private.app_installs where key = k) = daily_before - 1, 'from her free credits';
  assert (r->>'credits_remaining')::int = daily_before - 1;
  assert not public.ad_unlock_available(she, 'template', 'doll-box'), 'spent';

  r := public.admit_unlocked_job(she, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert r->>'code' = 'pro_required', format('one try, one job: %s', r);
  assert public.ad_reward_overview(she, false, 'atid-try-1', 'verified', 'Sandbox')->'unlock'->'active' = '[]'::jsonb,
    'nothing left to show';
end $$;

-- 7. A refunded job gives the try back, for the rest of its 30 minutes.
do $$
declare
  she uuid := '00000000-0000-0000-0000-0000000a7e01';
  k text := private.keyed_hash('app_transaction', 'atid-try-1');
  j uuid;
  j2 uuid;
  r jsonb;
begin
  select job_id into j from private.ad_unlocks where transaction_id = 'tx-try-1';
  assert public.fail_job(j, 'provider_failed', 'This creation failed. Your credit was refunded.'), 'failed';
  assert (select job_id is null and used_at is null from private.ad_unlocks where transaction_id = 'tx-try-1'),
    'the try is back';
  assert (select daily from private.app_installs where key = k) = 2, 'and so is the credit';
  r := public.admit_unlocked_job(she, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('used again: %s', r);
  j2 := (r->>'job_id')::uuid;
  assert (select job_id from private.ad_unlocks where transaction_id = 'tx-try-1') = j2, 'spent on the new job';

  -- She cancels the new one: back again. Refunding the first job again changes nothing.
  perform public.cancel_job(j2, she);
  assert (select job_id is null from private.ad_unlocks where transaction_id = 'tx-try-1'), 'a cancel gives it back';
  perform public.release_credits(j);
  assert (select job_id is null from private.ad_unlocks where transaction_id = 'tx-try-1'), 'once';
  assert (select daily from private.app_installs where key = k) = 2, 'and every credit exactly once';

  -- Its 30 minutes run out.
  update private.ad_unlocks set expires_at = now() - interval '1 second' where transaction_id = 'tx-try-1';
  assert not public.ad_unlock_available(she, 'template', 'doll-box'), 'an ended try';
  r := public.admit_unlocked_job(she, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-1', p_install_status => 'verified');
  assert r->>'code' = 'pro_required', format('expired: %s', r);
end $$;

-- 8. The free retry of a result a try paid for needs no new try and no credit.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000a7e05';
  token uuid;
  r jsonb;
  original uuid;
  retry uuid;
begin
  perform public.wallet_state(u, 'atid-try-5', 'verified', 'Sandbox');
  select reward_token into token
    from public.issue_ad_unlock_token(u, false, 'style', 'fantasy', 'atid-try-5', 'verified', 'Sandbox');
  assert (select outcome from public.redeem_ad_reward('tx-try-5', token, '1406702504', 1, 'credit')) = 'granted';
  r := public.admit_unlocked_job(u, 'style', 'fantasy', 'text_to_image', 'test',
                                 p_app_transaction_id => 'atid-try-5', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('admitted: %s', r);
  original := (r->>'job_id')::uuid;
  update public.jobs set status = 'completed', outputs = '[{"base64":"AAAA"}]' where id = original;

  assert public.ad_unlock_available(u, 'style', 'fantasy', original), 'the retry rides on the original''s try';
  r := public.admit_unlocked_job(u, 'style', 'fantasy', 'text_to_image', 'test', p_retry_of => original,
                                 p_app_transaction_id => 'atid-try-5', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('the free retry: %s', r);
  retry := (r->>'job_id')::uuid;
  assert (select cost from public.jobs where id = retry) = 0, 'free, as every retry';
  assert (select job_id from private.ad_unlocks where transaction_id = 'tx-try-5') = original,
    'the try stays with the original';

  assert not public.ad_unlock_available(u, 'style', 'neon', original), 'not for another Pro style';
  r := public.admit_unlocked_job(u, 'style', 'neon', 'text_to_image', 'test', p_retry_of => original,
                                 p_app_transaction_id => 'atid-try-5', p_install_status => 'verified');
  assert r->>'code' = 'pro_required', format('another style: %s', r);
  r := public.admit_unlocked_job(u, 'style', 'fantasy', 'text_to_image', 'test', p_retry_of => gen_random_uuid(),
                                 p_app_transaction_id => 'atid-try-5', p_install_status => 'verified');
  assert r->>'code' = 'pro_required', format('a job no try paid for: %s', r);
end $$;

-- 9. Every other gate still applies, and a refusal spends nothing.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000a7e06';
  k text := private.keyed_hash('app_transaction', 'atid-try-6');
  token uuid;
  r jsonb;
begin
  perform public.wallet_state(u, 'atid-try-6', 'verified', 'Sandbox');
  select reward_token into token
    from public.issue_ad_unlock_token(u, false, 'template', 'figurine', 'atid-try-6', 'verified', 'Sandbox');
  perform public.redeem_ad_reward('tx-try-6', token, '1406702504', 1, 'credit');

  r := public.admit_unlocked_job(u, 'template', 'figurine', 'restyle', 'test', p_template_id => 'figurine',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-6', p_install_status => 'verified',
                                 p_blocked_category => 'sexual');
  assert r->>'code' = 'content_blocked', format('the prompt policy: %s', r);
  assert exists (select 1 from private.strikes where user_id = u), 'a strike, as always';
  assert public.ad_unlock_available(u, 'template', 'figurine'), 'the try isn''t spent on a refusal';

  perform public.ops_pause_ai('all', 1, 'rewarded unlocks test');
  r := public.admit_unlocked_job(u, 'template', 'figurine', 'restyle', 'test', p_template_id => 'figurine',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-6', p_install_status => 'verified');
  assert r->>'code' = 'ai_paused', format('the owner''s pause: %s', r);
  perform public.ops_resume_ai();

  update private.app_installs set daily = 0 where key = k;
  r := public.admit_unlocked_job(u, 'template', 'figurine', 'restyle', 'test', p_template_id => 'figurine',
                                 p_input_images => 1, p_app_transaction_id => 'atid-try-6', p_install_status => 'verified');
  assert r->>'code' = 'insufficient_credits' and (r->>'status')::int = 402, format('a try still costs a credit: %s', r);
  assert public.ad_unlock_available(u, 'template', 'figurine'), 'still unspent';
  assert not exists (select 1 from public.jobs where user_id = u and status <> 'failed'), 'nothing admitted';
end $$;

-- 10. Pro by the time admission runs (a purchase that just landed): no try needed.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000a7e04';
  r jsonb;
begin
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('otx-try-pro', u, 'app.glowlit.pro.monthly', now() + interval '1 month');
  r := public.admit_unlocked_job(u, 'template', 'doll-box', 'restyle', 'test', p_template_id => 'doll-box',
                                 p_input_images => 1);
  assert (r->>'ok')::boolean, format('Pro: %s', r);
  assert not (public.ad_reward_overview(u, true)->'unlock'->>'eligible')::boolean, 'and no ads for Pro';
end $$;

-- 11. Sign in with Apple moves her tries; the sweep and account deletion remove them.
do $$
declare
  from_user uuid := '00000000-0000-0000-0000-0000000a7e07';
  to_user uuid := '00000000-0000-0000-0000-0000000a7e08';
begin
  insert into private.ad_unlocks (user_id, transaction_id, unlock_type, unlock_id, expires_at)
    values (from_user, 'tx-try-merge', 'template', 'paris', now() + interval '20 minutes');
  perform public.merge_accounts(from_user, to_user);
  assert (select user_id from private.ad_unlocks where transaction_id = 'tx-try-merge') = to_user, 'her try comes along';
  assert public.ad_unlock_available(to_user, 'template', 'paris');

  insert into private.ad_unlocks (user_id, transaction_id, unlock_type, unlock_id, granted_at, expires_at)
    values (to_user, 'tx-try-old', 'style', 'clay', now() - interval '26 hours', now() - interval '25 hours');
  perform public.sweep_ad_rewards();
  assert not exists (select 1 from private.ad_unlocks where transaction_id = 'tx-try-old'), 'gone a day after it ended';
  assert exists (select 1 from private.ad_unlocks where transaction_id = 'tx-try-merge'), 'a live try stays';

  delete from auth.users where id = to_user;
  assert not exists (select 1 from private.ad_unlocks where transaction_id = 'tx-try-merge'), 'gone with the account';
end $$;

-- 12. Clients can't see, mint or spend a try.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a7e01', false);
do $$
declare
  denied boolean := false;
  visible int := 0;
begin
  begin
    select count(*) into visible from private.ad_unlocks;
  exception when insufficient_privilege then
    visible := 0;
  end;
  assert visible = 0, 'clients see no tries, not even their own';
  begin
    perform public.admit_unlocked_job('00000000-0000-0000-0000-0000000a7e01', 'template', 'doll-box', 'restyle', 'test');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'clients cannot spend a try';
  denied := false;
  begin
    perform public.issue_ad_unlock_token('00000000-0000-0000-0000-0000000a7e01', false, 'template', 'doll-box');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'clients cannot mint one';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- Clean up, and put the day's breaker counts back.
do $$
begin
  delete from private.strikes where user_id = '00000000-0000-0000-0000-0000000a7e06';
  delete from auth.users where id in (
    '00000000-0000-0000-0000-0000000a7e01', '00000000-0000-0000-0000-0000000a7e02',
    '00000000-0000-0000-0000-0000000a7e03', '00000000-0000-0000-0000-0000000a7e04',
    '00000000-0000-0000-0000-0000000a7e05', '00000000-0000-0000-0000-0000000a7e06',
    '00000000-0000-0000-0000-0000000a7e07');
  delete from private.app_installs
   where key in (select private.keyed_hash('app_transaction', a)
                   from unnest(array['atid-try-1', 'atid-try-3', 'atid-try-5', 'atid-try-6']) a);
  delete from private.ai_usage_daily where day = (now() at time zone 'utc')::date;
  insert into private.ai_usage_daily select * from try_saved_usage;
end $$;

select 'all rewarded unlock tests passed' as result;
