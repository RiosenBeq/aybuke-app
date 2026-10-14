-- Results that never reached the app are refunded exactly once. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000b2');

-- 1. Delivery is recorded once, only for the job's owner and only while there are results.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  other uuid := '00000000-0000-0000-0000-0000000000b2';
  j uuid := gen_random_uuid();
  first_delivery timestamptz;
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, status, outputs)
    values (j, u, 'magic_edit', 'test', 1, 'completed', '[{"base64":"AAAA"}]');
  assert public.deliver_outputs(j, other) is null, 'another user gets nothing';
  assert (select delivered_at from public.jobs where id = j) is null, 'nor marks it delivered';
  assert public.deliver_outputs(j, u) = '[{"base64":"AAAA"}]'::jsonb, 'the owner gets the results';
  assert (select delivered_at from public.jobs where id = j) is not null, 'delivery is recorded';
  first_delivery := now() - interval '5 minutes';
  update public.jobs set delivered_at = first_delivery where id = j;
  assert public.deliver_outputs(j, u) is not null, 'a lost response can be fetched again';
  assert (select delivered_at from public.jobs where id = j) = first_delivery, 'the first delivery time stays';
  update public.jobs set outputs = null where id = j;
  assert public.deliver_outputs(j, u) is null, 'nothing to hand over once confirmed';
end $$;

-- 2. A finished job the app never received is refunded when its hour is up, exactly once.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  j uuid := gen_random_uuid();
  fresh uuid := gen_random_uuid();
begin
  perform public.refresh_wallet(u, false);
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j, u, 'magic_edit', 'test', 1);
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (fresh, u, 'magic_edit', 'test', 1);
  perform public.reserve_credits(u, false, 1, j);
  perform public.reserve_credits(u, false, 1, fresh);
  update public.jobs set status = 'completed', outputs = '[{"base64":"AAAA"}]', updated_at = now() - interval '61 minutes'
   where id = j;
  update public.jobs set status = 'completed', outputs = '[{"base64":"BBBB"}]', updated_at = now() - interval '10 minutes'
   where id = fresh;
  assert (select daily from public.credit_wallets where user_id = u) = 1, 'two credits are held';

  perform public.sweep_jobs();
  assert (select status from public.jobs where id = j) = 'failed', 'the undelivered job fails';
  assert (select error_code from public.jobs where id = j) = 'undelivered';
  assert (select outputs from public.jobs where id = j) is null, 'its results are deleted';
  assert (select daily from public.credit_wallets where user_id = u) = 2, 'and its credit comes back';
  assert (select outputs from public.jobs where id = fresh) is not null, 'a result inside its hour waits';

  perform public.sweep_jobs();
  assert (select count(*) from public.credit_ledger where job_id = j and kind = 'release') = 1, 'refunded once';
  assert (select daily from public.credit_wallets where user_id = u) = 2, 'a second sweep changes nothing';
end $$;

-- 3. Delivered but never confirmed: refunded once a day per user at most.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
  first_job uuid := gen_random_uuid();
  second_job uuid := gen_random_uuid();
  confirmed uuid := gen_random_uuid();
begin
  perform public.refresh_wallet(u, false);
  insert into public.jobs (id, user_id, operation, endpoint, cost) values
    (first_job, u, 'magic_edit', 'test', 1), (second_job, u, 'magic_edit', 'test', 1), (confirmed, u, 'enhance', 'test', 1);
  perform public.reserve_credits(u, false, 1, first_job);
  perform public.reserve_credits(u, false, 1, second_job);
  perform public.reserve_credits(u, false, 1, confirmed);
  update public.jobs
     set status = 'completed', outputs = '[{"base64":"AAAA"}]', delivered_at = now() - interval '2 hours',
         updated_at = now() - interval '2 hours'
   where id in (first_job, second_job);
  -- Confirmed downloads ("got it") have no results left to sweep.
  update public.jobs set status = 'completed', outputs = null, delivered_at = now() - interval '2 hours',
         updated_at = now() - interval '2 hours'
   where id = confirmed;
  assert (select daily from public.credit_wallets where user_id = u) = 0, 'three credits are held';

  perform public.sweep_jobs();
  assert (select count(*) from public.jobs where id in (first_job, second_job) and error_code = 'unconfirmed') = 1,
    'one unconfirmed result is refunded';
  assert (select count(*) from public.jobs where id in (first_job, second_job) and status = 'completed') = 1,
    'the other one stays paid';
  assert (select count(*) from public.jobs where id in (first_job, second_job) and outputs is not null) = 0,
    'both are deleted after the hour';
  assert (select daily from public.credit_wallets where user_id = u) = 1, 'exactly one credit comes back';
  assert (select status from public.jobs where id = confirmed) = 'completed', 'a confirmed download stays paid';
  assert (select count(*) from public.credit_ledger where job_id = confirmed and kind = 'release') = 0;
end $$;

-- 4. Cancelling: a running job and a finished job the app never received are refunded
--    right away; on a delivered job a plain DELETE is the "got it" that clears the
--    results, and a cancel (the app gave up waiting) settles it like the cleanup.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  running uuid := gen_random_uuid();
  unreceived uuid := gen_random_uuid();
  received uuid := gen_random_uuid();
  lost uuid := gen_random_uuid();
  lost_again uuid := gen_random_uuid();
  result jsonb;
  before int;
begin
  perform public.grant_pack(u, 10, 'tx-unclaimed-4');
  insert into public.jobs (id, user_id, operation, endpoint, cost) values
    (running, u, 'magic_edit', 'test', 1), (unreceived, u, 'magic_edit', 'test', 1), (received, u, 'magic_edit', 'test', 1),
    (lost, u, 'magic_edit', 'test', 1), (lost_again, u, 'magic_edit', 'test', 1);
  perform public.reserve_credits(u, false, 1, running);
  perform public.reserve_credits(u, false, 1, unreceived);
  perform public.reserve_credits(u, false, 1, received);
  perform public.reserve_credits(u, false, 1, lost);
  perform public.reserve_credits(u, false, 1, lost_again);
  update public.jobs set status = 'processing' where id = running;
  update public.jobs set status = 'completed', outputs = '[{"base64":"AAAA"}]'
   where id in (unreceived, received, lost, lost_again);
  perform public.deliver_outputs(received, u);
  perform public.deliver_outputs(lost, u);
  perform public.deliver_outputs(lost_again, u);
  select daily + subscription + purchased into before from public.credit_wallets where user_id = u;

  result := public.cancel_job(running, u, true);
  assert result->>'status' = 'cancelled', format('running job cancelled, got %s', result);
  assert (result->>'credits_remaining')::int = before + 1, 'and refunded';

  result := public.cancel_job(unreceived, u);
  assert result->>'status' = 'cancelled', 'an unreceived result is cancelled, whatever the intent';
  assert (result->>'credits_remaining')::int = before + 2, 'and refunded';
  assert (select outputs from public.jobs where id = unreceived) is null, 'its results are deleted';

  result := public.cancel_job(received, u);
  assert result->>'status' = 'completed', 'a received result is confirmed, not cancelled';
  assert (result->>'credits_remaining')::int = before + 2, 'and stays paid';
  assert (select outputs from public.jobs where id = received) is null, 'its results are deleted';
  result := public.cancel_job(received, u, true);
  assert result->>'status' = 'completed' and (result->>'credits_remaining')::int = before + 2,
    'a cancel after the "got it" changes nothing';

  -- The response with the results was lost and the app gave up: refunded, once a day.
  result := public.cancel_job(lost, u, true);
  assert result->>'status' = 'failed' and (result->>'credits_remaining')::int = before + 3,
    format('lost result refunded, got %s', result);
  assert (select error_code from public.jobs where id = lost) = 'unconfirmed';
  result := public.cancel_job(lost_again, u, true);
  assert result->>'status' = 'completed' and (result->>'credits_remaining')::int = before + 3,
    'the second one that day stays paid';
  assert (select outputs from public.jobs where id = lost_again) is null, 'its results are deleted anyway';

  result := public.cancel_job(unreceived, u, true);
  assert result->>'status' = 'cancelled' and (result->>'credits_remaining')::int = before + 3, 'cancelling twice refunds once';
  assert public.cancel_job(received, '00000000-0000-0000-0000-0000000000b2') is null, 'only the owner can cancel';
  assert (select count(*) from public.credit_ledger where job_id in (running, unreceived, lost) and kind = 'release') = 3;
  assert (select count(*) from public.credit_ledger where job_id in (received, lost_again) and kind = 'release') = 0;
end $$;

-- 5. Failing a running job refunds it in the same step, once; a failed free retry
--    gives the retry back; a finished job can't be failed afterwards.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
  j uuid := gen_random_uuid();
  original uuid := gen_random_uuid();
  retry uuid := gen_random_uuid();
  done uuid := gen_random_uuid();
  before int;
begin
  perform public.grant_pack(u, 5, 'tx-unclaimed-5');
  insert into public.jobs (id, user_id, operation, endpoint, cost, status) values
    (j, u, 'magic_edit', 'test', 1, 'processing'),
    (original, u, 'magic_edit', 'test', 1, 'completed'),
    (done, u, 'magic_edit', 'test', 1, 'completed');
  update public.jobs set retried = true where id = original;
  insert into public.jobs (id, user_id, operation, endpoint, cost, status, retry_of)
    values (retry, u, 'magic_edit', 'test', 0, 'processing', original);
  perform public.reserve_credits(u, false, 1, j);
  select daily + subscription + purchased into before from public.credit_wallets where user_id = u;

  assert public.fail_job(j, 'provider_failed', 'This creation failed. Your credit was refunded.'), 'a running job fails';
  assert (select status from public.jobs where id = j) = 'failed';
  assert (select daily + subscription + purchased from public.credit_wallets where user_id = u) = before + 1, 'and is refunded';
  assert not public.fail_job(j, 'timeout', 'again'), 'only once';
  assert (select error_code from public.jobs where id = j) = 'provider_failed', 'the first reason stays';
  assert (select count(*) from public.credit_ledger where job_id = j and kind = 'release') = 1;

  assert public.fail_job(retry, 'provider_failed', 'x'), 'a free retry fails';
  assert (select retried from public.jobs where id = original) = false, 'and the retry can be used again';
  assert not public.fail_job(done, 'timeout', 'late'), 'a finished job stays finished';
  assert (select status from public.jobs where id = done) = 'completed';
end $$;

-- 6. Clients can't call the job functions.
do $$
begin
  assert not has_function_privilege('authenticated', 'public.fail_job(uuid, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.deliver_outputs(uuid, uuid)', 'execute');
  assert not has_function_privilege('authenticated', 'public.settle_unconfirmed(uuid)', 'execute');
  assert not has_function_privilege('authenticated', 'public.cancel_job(uuid, uuid, boolean)', 'execute');
  assert not has_function_privilege('anon', 'public.cancel_job(uuid, uuid, boolean)', 'execute');
end $$;

delete from auth.users where id in ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b2');

select 'all unclaimed result tests passed' as result;
