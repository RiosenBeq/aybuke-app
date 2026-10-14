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
--   * a DELETE on a finished job the app never received can't be a "got it":
--     cancel_job() cancels and refunds it right away.
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

-- DELETE /ai-image?job_id=…: cancels and refunds a job that is still running
-- or that finished without its results ever reaching the app; on a delivered
-- job it is the app's "got it" and only clears the results. Returns
-- { status, credits_remaining } (null when the job isn't the user's).
create or replace function public.cancel_job(p_job uuid, p_user uuid)
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
    j.status := 'cancelled';
  elsif j.status = 'completed' then
    update public.jobs set outputs = null, updated_at = now() where id = p_job;
  end if;
  if balance is null then
    select daily + subscription + purchased into balance from public.credit_wallets where user_id = p_user;
  end if;
  return jsonb_build_object('status', j.status, 'credits_remaining', balance);
end $$;

-- Fails and refunds jobs that never finished; refunds results that never
-- reached the app (see above) when their hour is up and clears every stored
-- result after an hour; deletes job rows after 30 days and reports after 12
-- months. Schedule with pg_cron every 5 minutes (backend/README.md).
create or replace function public.sweep_jobs()
returns void
language plpgsql security definer set search_path = public as $$
declare
  j record;
  refund boolean;
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

  -- Finished results nobody confirmed within the hour. Rows another request
  -- holds right now (a poll or a DELETE) wait for the next run.
  for j in
    select id, user_id, delivered_at
      from public.jobs
     where status = 'completed' and outputs is not null and updated_at < now() - interval '1 hour'
     order by updated_at
       for update skip locked
  loop
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
       where id = j.id;
      perform public.release_credits(j.id);
    else
      update public.jobs set outputs = null where id = j.id;
    end if;
  end loop;

  update public.jobs set outputs = null
   where outputs is not null and status <> 'completed' and updated_at < now() - interval '1 hour';
  delete from public.jobs where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '12 months';
end $$;

revoke execute on function public.deliver_outputs(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.cancel_job(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.sweep_jobs() from public, anon, authenticated;
grant execute on function public.deliver_outputs(uuid, uuid) to service_role;
grant execute on function public.cancel_job(uuid, uuid) to service_role;
