-- RevenueCat customers waiting to be deleted.
-- ----------------------------------------------------------------------------
-- Deleting an account must also delete its RevenueCat customers (the privacy
-- policy promises it). Without REVENUECAT_SECRET_KEY, or while RevenueCat
-- can't be reached, that used to be skipped with a warning. Now DELETE
-- /account queues the user ids here first, then works through the queue
-- whenever the key is set: at every account deletion and from the scheduled
-- POST /account/revenuecat-deletions (backend/README.md). A row is deleted as
-- soon as RevenueCat has deleted that customer (or never had it).
--
-- Only the pseudonymous user id is kept, with no link to auth.users (the user
-- is already gone), and only until RevenueCat confirms. Service role only.

create table public.pending_revenuecat_deletions (
  user_id uuid primary key,
  created_at timestamptz not null default now(),
  attempts int not null default 0,
  last_attempt_at timestamptz,
  last_error text
);
create index pending_revenuecat_deletions_created_idx on public.pending_revenuecat_deletions (created_at);

-- No policies: only the service role (Edge Functions) can read or write it.
alter table public.pending_revenuecat_deletions enable row level security;
revoke all on table public.pending_revenuecat_deletions from anon, authenticated;
grant all on table public.pending_revenuecat_deletions to service_role;
