-- A subscription only moves forward (see resolveEntitlement in _shared/apple.ts).
-- ----------------------------------------------------------------------------
-- An older signed transaction (a stale cache, another device) used to overwrite
-- the stored row whenever the user had no active row of her own: an earlier
-- expiry, or an unrevoked state after a refund, replaced the newer one. Now
-- record_entitlement() is the only write path and, in one statement, refuses a
-- transaction that expires before the stored one. A revocation always lands.
-- A revoked row comes back only for a later transaction: the one from before
-- the refund has the same expiry, so it is refused too.

create or replace function public.record_entitlement(
  p_user uuid,
  p_original_transaction_id text,
  p_product_id text,
  p_expires_at timestamptz,
  p_revoked boolean,
  p_environment text,
  p_is_trial boolean
)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.entitlements as e
    (original_transaction_id, user_id, product_id, expires_at, revoked, environment, is_trial, updated_at)
    values (p_original_transaction_id, p_user, p_product_id, p_expires_at, p_revoked, p_environment, p_is_trial, now())
    on conflict (original_transaction_id) do update
      set user_id = excluded.user_id,
          product_id = excluded.product_id,
          expires_at = excluded.expires_at,
          revoked = excluded.revoked,
          environment = excluded.environment,
          is_trial = excluded.is_trial,
          updated_at = excluded.updated_at
      where excluded.revoked
         or not coalesce(
              e.expires_at is not null
              and (excluded.expires_at is null
                   or excluded.expires_at < e.expires_at
                   or (e.revoked and excluded.expires_at = e.expires_at)),
              false);
  -- False when the stored transaction is newer: nothing changed.
  return found;
end $$;

revoke execute on function public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)
  from public, anon, authenticated;
grant execute on function public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)
  to service_role;

comment on column public.entitlements.trial_granted is
  'Trial credits were granted for this subscription: once per original_transaction_id, never again.';
