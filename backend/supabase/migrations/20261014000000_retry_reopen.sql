-- Likeness Lock: a free retry that times out doesn't use up the retry, so the
-- original result can be retried again (ai-image's failJob does the same for
-- provider failures).

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
  update public.jobs set outputs = null where outputs is not null and updated_at < now() - interval '1 hour';
  delete from public.jobs where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '12 months';
end $$;

revoke execute on function public.sweep_jobs() from public, anon, authenticated;
