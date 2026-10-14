-- Results the app never received are refunded ("failed edits are always refunded").
-- ----------------------------------------------------------------------------
-- A finished job used to count as paid even when the app had lost its
-- connection and never got the images: sweep_jobs() just cleared them after
-- an hour. Now the server records when it hands the results to the app
-- (jobs.delivered_at, set by deliver_outputs() in the poll that returns them):
--
--   * finished but never handed over (the app stopped waiting): when the
--     cleanup clears the results after an hour, the job is failed with
--     error_code 'undelivered' and refunded, exactly once;
--   * handed over but never confirmed (the confirming DELETE never arrived,
--     or the download broke on the way): refunded the same way, once a day
--     per user at most ('unconfirmed'), so a client can't keep both the
--     images and the credit by skipping the confirmation;
--   * DELETE /ai-image?job_id=… (cancel_job()) stops a running job and
--     refunds it, and so it does for a finished job the app never received.
--     On a delivered job a plain DELETE is the app's "got it" (the results
--     are cleared, the job stays paid), while `intent=cancel` (the app gave
--     up waiting) settles it like the cleanup does.
--
-- release_credits() stays the only refund path, and it refunds a job at most
-- once whichever path gets there first.

alter table public.jobs add column delivered_at timestamptz;

-- Jobs finished before this migration were handed over the old way: treat
-- them as delivered, so nothing is refunded twice or by surprise.
update public.jobs set delivered_at = updated_at where status = 'completed' and delivered_at is null;

-- Hands a finished job's results to the app (the poll that returns them) and
-- records the first delivery. Null when there is nothing to hand over.
create or replace function public.deliver_outputs(p_job uuid, p_user uuid)
returns jsonb
language sql security definer set search_path = public as $$
  update public.jobs
     set delivered_at = coalesce(delivered_at, now())
   where id = p_job and user_id = p_user and status = 'completed' and outputs is not null
  returning outputs
$$;

-- Deletes the results of a finished job the app never confirmed. Refunded
-- when they never reached the app ('undelivered'), or when they did but the
-- user has had no such refund in the last day ('unconfirmed'); otherwise the
-- job stays paid. Returns true when it refunded. The caller locks the row.
create or replace function public.settle_unconfirmed(p_job uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  j public.jobs;
  refund boolean;
begin
  select * into j from public.jobs where id = p_job;
  -- Confirmed downloads ("got it") have no results left and stay paid.
  if not found or j.status <> 'completed' or j.outputs is null then
    return false;
  end if;
  refund := j.delivered_at is null or not exists (
    select 1 from public.jobs earlier
     where earlier.user_id = j.user_id and earlier.error_code = 'unconfirmed'
       and earlier.updated_at > now() - interval '1 day'
  );
  if refund then
    update public.jobs
       set status = 'failed',
           error_code = case when j.delivered_at is null then 'undelivered' else 'unconfirmed' end,
           error_message = 'Your result never reached the app. Your credit was refunded.',
           outputs = null,
           updated_at = now()
     where id = p_job;
    perform public.release_credits(p_job);
  else
    update public.jobs set outputs = null where id = p_job;
  end if;
  return refund;
end $$;

-- DELETE /ai-image?job_id=…: cancels and refunds a job that is still running
-- or that finished without its results ever reaching the app. On a delivered
-- job, `p_cancel` false is the app's "got it" (the results are cleared) and
-- true settles it with settle_unconfirmed(). Returns { status,
-- credits_remaining }, or null when the job isn't the user's.
create or replace function public.cancel_job(p_job uuid, p_user uuid, p_cancel boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  j public.jobs;
  balance int;
begin
  select * into j from public.jobs where id = p_job and user_id = p_user for update;
  if not found then
    return null;
  end if;
  if j.status in ('queued', 'processing') or (j.status = 'completed' and j.delivered_at is null) then
    update public.jobs set status = 'cancelled', outputs = null, updated_at = now() where id = p_job;
    balance := public.release_credits(p_job);
  elsif j.status = 'completed' and p_cancel then
    perform public.settle_unconfirmed(p_job);
  elsif j.status = 'completed' then
    update public.jobs set outputs = null, updated_at = now() where id = p_job;
  end if;
  if balance is null then
    select daily + subscription + purchased into balance from public.credit_wallets where user_id = p_user;
  end if;
  return jsonb_build_object('status', (select status from public.jobs where id = p_job), 'credits_remaining', balance);
end $$;

-- Fails and refunds jobs that never finished; settles results nobody
-- confirmed when their hour is up (see above), and clears every other stored
-- result after an hour; deletes job rows after 30 days and reports after 12
-- months. Schedule with pg_cron every 5 minutes (backend/README.md).
create or replace function public.sweep_jobs()
returns void
language plpgsql security definer set search_path = public as $$
declare
  j record;
begin
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

  -- Rows another request holds right now (a poll or a DELETE) wait for the next run.
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
end $$;

revoke execute on function public.deliver_outputs(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.settle_unconfirmed(uuid) from public, anon, authenticated;
revoke execute on function public.cancel_job(uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.sweep_jobs() from public, anon, authenticated;
grant execute on function public.deliver_outputs(uuid, uuid) to service_role;
grant execute on function public.settle_unconfirmed(uuid) to service_role;
grant execute on function public.cancel_job(uuid, uuid, boolean) to service_role;
