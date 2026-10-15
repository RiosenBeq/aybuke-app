-- Sign in with Apple's tables stay server-only.
-- ----------------------------------------------------------------------------
-- apple_accounts (Apple refresh tokens) and merged_users have RLS on and no
-- policies, so clients already read nothing. Supabase's default privileges
-- still grant every new public table to anon and authenticated; take those
-- grants away too, so a policy added by mistake later can't expose a token.
-- Only the service role (the `account` Edge Function) uses them.

revoke all on table public.apple_accounts from anon, authenticated;
revoke all on table public.merged_users from anon, authenticated;
