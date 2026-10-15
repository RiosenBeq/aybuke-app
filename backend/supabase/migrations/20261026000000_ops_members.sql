-- Owner view of members: how many joined, signed in with Apple, have Pro, bought packs.
-- Run in Supabase › SQL Editor (service role):
--   select public.ops_members_summary();
--   select * from public.ops_members(50);
-- No emails or tokens: ids, dates, counts and balances only.

-- Covering indexes for foreign keys the performance advisor flagged
-- (account deletion cascades through them).
create index if not exists credit_ledger_user_id_idx on public.credit_ledger (user_id);
create index if not exists jobs_retry_of_idx on public.jobs (retry_of);
create index if not exists reports_job_id_idx on public.reports (job_id);

create or replace function public.ops_members_summary()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_users jsonb;
  v_pro jsonb;
  v_packs jsonb;
  v_ads jsonb;
begin
  select jsonb_build_object(
           'total', count(*),
           'anonymous', count(*) filter (where u.is_anonymous),
           'signed_in_with_apple', count(*) filter (where exists (
              select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')),
           'new_today', count(*) filter (where u.created_at >= date_trunc('day', now())),
           'new_7_days', count(*) filter (where u.created_at >= now() - interval '7 days'),
           'new_30_days', count(*) filter (where u.created_at >= now() - interval '30 days'),
           'active_7_days', count(*) filter (where u.last_sign_in_at >= now() - interval '7 days'))
    into v_users
    from auth.users u;

  select jsonb_build_object(
           'active_members', count(distinct e.user_id) filter (
              where not e.revoked and (e.expires_at is null or e.expires_at > now())),
           'yearly', count(distinct e.user_id) filter (
              where not e.revoked and e.expires_at > now() and e.product_id like '%yearly%'),
           'monthly', count(distinct e.user_id) filter (
              where not e.revoked and e.expires_at > now() and e.product_id like '%monthly%'),
           'ever_subscribed', count(distinct e.user_id),
           'revoked_or_refunded', count(*) filter (where e.revoked),
           'sandbox_rows', count(*) filter (where e.environment = 'Sandbox'))
    into v_pro
    from public.entitlements e
   where e.product_id like '%pro%';

  select jsonb_build_object(
           'buyers', count(distinct l.user_id),
           'packs_sold', count(*),
           'credits_sold', coalesce(sum(l.purchased), 0),
           'last_30_days', count(*) filter (where l.created_at >= now() - interval '30 days'))
    into v_packs
    from public.credit_ledger l
   where l.kind = 'grant_pack';

  select jsonb_build_object(
           'granted', count(*) filter (where r.status = 'granted'),
           'viewers', count(distinct r.user_id) filter (where r.status = 'granted'),
           'credits', coalesce(sum(r.credits), 0))
    into v_ads
    from public.ad_rewards r;

  return jsonb_build_object(
    'at', now(),
    'members', v_users,
    'pro', v_pro,
    'credit_packs', v_packs,
    'ad_rewards', v_ads,
    'credits_held', (select jsonb_build_object(
                       'daily', coalesce(sum(daily), 0),
                       'subscription', coalesce(sum(subscription), 0),
                       'purchased', coalesce(sum(purchased), 0))
                       from public.credit_wallets),
    'ai_jobs', (select jsonb_build_object(
                  'total', count(*),
                  'completed', count(*) filter (where status = 'completed'),
                  'last_7_days', count(*) filter (where created_at >= now() - interval '7 days'))
                  from public.jobs));
end $$;

create or replace function public.ops_members(p_limit int default 50)
returns table (
  user_id uuid,
  joined_at timestamptz,
  last_sign_in_at timestamptz,
  apple boolean,
  pro_product text,
  pro_until timestamptz,
  credits int,
  packs_bought bigint,
  ai_jobs bigint
)
language sql stable security definer
set search_path = ''
as $$
  select u.id,
         u.created_at,
         u.last_sign_in_at,
         exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple'),
         pro.product_id,
         pro.expires_at,
         coalesce(w.daily + w.subscription + w.purchased, 0),
         (select count(*) from public.credit_ledger l where l.user_id = u.id and l.kind = 'grant_pack'),
         (select count(*) from public.jobs j where j.user_id = u.id)
    from auth.users u
    left join public.credit_wallets w on w.user_id = u.id
    left join lateral (
      select e.product_id, e.expires_at
        from public.entitlements e
       where e.user_id = u.id and not e.revoked and e.product_id like '%pro%'
       order by e.expires_at desc nulls first
       limit 1) pro on true
   order by u.created_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 1000));
$$;

revoke execute on function public.ops_members_summary() from public, anon, authenticated;
revoke execute on function public.ops_members(int) from public, anon, authenticated;
grant execute on function public.ops_members_summary() to service_role;
grant execute on function public.ops_members(int) to service_role;
