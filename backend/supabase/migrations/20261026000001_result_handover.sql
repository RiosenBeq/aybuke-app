-- A result the app got stays paid (backend/README.md "Credit rules").
-- Replaces settle_unconfirmed() from 20261017 in place; that migration stays
-- as it was deployed.
--
--   * Clients read no job rows. The "Users read their jobs" policy let a
--     session read its own jobs, results included, through the Data API
--     (GET /rest/v1/jobs), which deliver_outputs() never sees: the result
--     counted as never delivered, so DELETE /ai-image (cancel_job) or the
--     sweep refunded it, every time, and the install's free credits never ran
--     out. The app reads jobs only through ai-image, which records the delivery.
--   * The once-a-day refund of a result that was handed over but never
--     confirmed ('unconfirmed') counts per user and per install (the job's
--     install_key: the App Store install or, without one, the address), like
--     the ad cap (20261023). Anonymous accounts of one install share it, so a
--     script can't make a new account for each refund.

drop policy if exists "Users read their jobs" on public.jobs;
revoke select on table public.jobs from anon, authenticated;

-- Deletes the results of a finished job the app never confirmed. Refunded
-- when they never reached the app ('undelivered'), or when they did but
-- neither the user nor the install has had such a refund in the last day
-- ('unconfirmed'); otherwise the job stays paid. Returns true when it
-- refunded. The caller locks the row.
create or replace function public.settle_unconfirmed(p_job uuid)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
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
     where earlier.error_code = 'unconfirmed'
       and earlier.updated_at > now() - interval '1 day'
       and (earlier.user_id = j.user_id or earlier.install_key = j.install_key)
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

revoke execute on function public.settle_unconfirmed(uuid) from public, anon, authenticated;
grant execute on function public.settle_unconfirmed(uuid) to service_role;
