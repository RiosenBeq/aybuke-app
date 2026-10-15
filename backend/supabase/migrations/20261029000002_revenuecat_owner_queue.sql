-- RevenueCat deletions by hand, until REVENUECAT_SECRET_KEY is set.
-- ----------------------------------------------------------------------------
-- Deleting an account queues its RevenueCat customers in
-- public.pending_revenuecat_deletions (20261018000000). Without the secret key
-- (and with pg_net off, so the hourly retry isn't scheduled) nothing works
-- through the queue, yet the privacy policy promises the deletion. So the
-- owner's daily digest (functions/owner-digest) lists what is waiting, with
-- the RevenueCat App User IDs (the deleted accounts' random ids, upper case as
-- the app sends them). The owner deletes each customer in the RevenueCat
-- dashboard (Customers), then marks them done here:
--
--   select public.ops_mark_revenuecat_deleted(array['<App User ID>', …]);
--
-- With the key set, the digest works through the queue itself first.

-- What is waiting, oldest first: the count, the oldest date and up to p_limit
-- ids, upper case (RevenueCat's App User ID).
create function public.ops_revenuecat_pending(p_limit int default 20)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'count', (select count(*) from public.pending_revenuecat_deletions),
    'oldest', (select min(created_at) from public.pending_revenuecat_deletions),
    'failed', (select count(*) from public.pending_revenuecat_deletions where attempts > 0),
    'app_user_ids', coalesce((
      select jsonb_agg(upper(p.user_id::text) order by p.created_at, p.user_id)
        from (select user_id, created_at from public.pending_revenuecat_deletions
               order by created_at, user_id
               limit greatest(0, least(coalesce(p_limit, 20), 200))) p), '[]'::jsonb))
$$;

-- The owner deleted these customers in RevenueCat: forget them. Either case,
-- with or without spaces; anything that isn't a queued id is ignored. Returns
-- how many were removed and how many still wait.
create function public.ops_mark_revenuecat_deleted(p_ids text[])
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_removed int;
begin
  with gone as (
    delete from public.pending_revenuecat_deletions d
     where d.user_id::text in (select lower(btrim(i)) from unnest(coalesce(p_ids, '{}')) i)
    returning 1
  )
  select count(*) into v_removed from gone;
  return jsonb_build_object(
    'removed', v_removed,
    'waiting', (select count(*) from public.pending_revenuecat_deletions));
end $$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.ops_revenuecat_pending(int)',
    'public.ops_mark_revenuecat_deleted(text[])'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
