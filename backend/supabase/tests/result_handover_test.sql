-- A result the app got stays paid (20261026000001). Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000f2'),
  ('00000000-0000-0000-0000-0000000000f3'),
  ('00000000-0000-0000-0000-0000000000f4');

-- 1. A client can't read a job's results past ai-image: no row is visible, not even her own.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000f1';
  r jsonb;
begin
  r := public.admit_job(u, 'magic_edit', 'test', p_input_images => 1,
                        p_app_transaction_id => 'atid-handover-1', p_install_status => 'verified');
  assert (r->>'ok')::boolean, format('admitted: %s', r);
  update public.jobs set status = 'completed', outputs = '[{"base64":"AAAA"}]' where id = (r->>'job_id')::uuid;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
do $$
declare
  visible int := 0;
begin
  -- No grant (production) or no policy (this test database grants select): nothing to see either way.
  begin
    select count(*) into visible from public.jobs where outputs is not null;
  exception when insufficient_privilege then
    visible := 0;
  end;
  assert visible = 0, 'a session reads no job rows, so it never gets results that weren''t handed over';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- 2. Delivered but never confirmed: refunded once a day per user and per install,
--    so new anonymous accounts on one App Store install can't each claim it.
do $$
declare
  siblings uuid[] := array['00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f3']::uuid[];
  first_user uuid := '00000000-0000-0000-0000-0000000000f1';
  elsewhere uuid := '00000000-0000-0000-0000-0000000000f4';
  install text := private.keyed_hash('app_transaction', 'atid-handover-1');
  u uuid;
  r jsonb;
  j uuid;
begin
  -- The job from block 1: handed over, then the app gave up instead of confirming.
  select id into j from public.jobs where user_id = first_user and status = 'completed';
  assert public.deliver_outputs(j, first_user) is not null, 'handed over';
  perform public.cancel_job(j, first_user, true);
  assert (select error_code from public.jobs where id = j) = 'unconfirmed', 'the first one is refunded';
  assert (select daily from private.app_installs where key = install) = 2, 'its credit is back';

  foreach u in array siblings loop
    r := public.admit_job(u, 'magic_edit', 'test', p_input_images => 1,
                          p_app_transaction_id => 'atid-handover-1', p_install_status => 'verified');
    assert (r->>'ok')::boolean, format('admitted: %s', r);
    j := (r->>'job_id')::uuid;
    update public.jobs set status = 'completed', outputs = '[{"base64":"BBBB"}]' where id = j;
    assert public.deliver_outputs(j, u) is not null, 'handed over';
    perform public.cancel_job(j, u, true);
    assert (select status from public.jobs where id = j) = 'completed', 'another account on the install stays paid';
    assert (select outputs from public.jobs where id = j) is null, 'its results are deleted';
    assert (select count(*) from public.credit_ledger where job_id = j and kind = 'release') = 0, 'nothing refunded';
  end loop;
  assert (select daily from private.app_installs where key = install) = 0, 'both sibling jobs stay paid';

  -- Another install is not affected.
  r := public.admit_job(elsewhere, 'magic_edit', 'test', p_input_images => 1,
                        p_app_transaction_id => 'atid-handover-2', p_install_status => 'verified');
  j := (r->>'job_id')::uuid;
  update public.jobs set status = 'completed', outputs = '[{"base64":"CCCC"}]' where id = j;
  perform public.deliver_outputs(j, elsewhere);
  perform public.cancel_job(j, elsewhere, true);
  assert (select error_code from public.jobs where id = j) = 'unconfirmed', 'another install gets its own';
  assert (select daily from private.app_installs where key = private.keyed_hash('app_transaction', 'atid-handover-2')) = 2;
end $$;

delete from auth.users where id in (
  '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2',
  '00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f4');
delete from private.app_installs
 where key in (private.keyed_hash('app_transaction', 'atid-handover-1'), private.keyed_hash('app_transaction', 'atid-handover-2'));

select 'all result handover tests passed' as result;
