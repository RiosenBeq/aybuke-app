-- "Report this image" (App Store Review Guideline 1.2) and tighter retention.
-- ----------------------------------------------------------------------------
-- reports  one row per report a user files about one of their results. Kept
--          12 months for safety review, deleted earlier with the account.
-- Results are only needed until the app downloads them, so sweep_jobs() now
-- also clears job outputs after an hour (provider CDN links expire then too).

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  job_id uuid references public.jobs (id) on delete set null,
  reason text not null check (reason in ('offensive', 'sexual', 'mismatch', 'other')),
  details text check (char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);
create index reports_user_created_idx on public.reports (user_id, created_at desc);
create index reports_open_idx on public.reports (created_at) where status = 'open';

alter table public.reports enable row level security;
create policy "Users read their reports" on public.reports for select using ((select auth.uid()) = user_id);

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
    returning id
  loop
    perform public.release_credits(j.id);
  end loop;
  update public.jobs set outputs = null where outputs is not null and updated_at < now() - interval '1 hour';
  delete from public.jobs where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '12 months';
end $$;

revoke execute on function public.sweep_jobs() from public, anon, authenticated;
