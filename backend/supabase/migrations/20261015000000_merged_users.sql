-- Anonymous users merged into an account after Sign in with Apple.
-- ----------------------------------------------------------------------------
-- RevenueCat keeps a purchase made while anonymous on that anonymous customer
-- (logging in from a custom id moves nothing), so deleting the account must
-- delete those customers too. The `account` Edge Function writes a row in
-- /account/link and reads them on DELETE /account. The rows go with the account.

create table public.merged_users (
  account_id uuid not null references auth.users (id) on delete cascade,
  anonymous_id uuid not null,
  merged_at timestamptz not null default now(),
  primary key (account_id, anonymous_id)
);
-- No policies: only the service role (Edge Functions) can read or write it.
alter table public.merged_users enable row level security;
