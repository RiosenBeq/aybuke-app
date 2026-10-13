-- Behavioural tests for reports and retention. Run with backend/scripts/test-db.sh
-- (after credits_test.sql). Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000003');

-- 1. Reports keep a valid reason, cap details and survive job cleanup.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000003';
  j uuid := gen_random_uuid();
  r uuid;
  rejected boolean := false;
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, created_at)
    values (j, u, 'magic_edit', 'test', 1, now() - interval '31 days');
  insert into public.reports (user_id, job_id, reason, details) values (u, j, 'mismatch', 'Not what I asked for') returning id into r;
  begin
    insert into public.reports (user_id, reason) values (u, 'spam');
  exception when check_violation then
    rejected := true;
  end;
  assert rejected, 'unknown reasons must be rejected';

  perform public.sweep_jobs();
  assert (select count(*) from public.jobs where id = j) = 0, 'old job rows are deleted';
  assert (select job_id from public.reports where id = r) is null, 'report survives with the job link cleared';
end $$;

-- 2. Outputs are cleared an hour after the job finished; old reports expire.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000003';
  fresh uuid := gen_random_uuid();
  stale uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, status, outputs, updated_at)
    values (fresh, u, 'enhance', 'test', 1, 'completed', '[{"url":"https://cdn/a.jpg"}]', now() - interval '10 minutes'),
           (stale, u, 'enhance', 'test', 1, 'completed', '[{"url":"https://cdn/b.jpg"}]', now() - interval '2 hours');
  insert into public.reports (user_id, reason, created_at) values (u, 'other', now() - interval '13 months');
  perform public.sweep_jobs();
  assert (select outputs from public.jobs where id = fresh) is not null, 'recent outputs stay available';
  assert (select outputs from public.jobs where id = stale) is null, 'outputs older than an hour are cleared';
  assert (select count(*) from public.reports where created_at < now() - interval '12 months') = 0, 'reports expire after 12 months';
end $$;

-- 3. RLS: users see only their own reports; deleting the account removes them.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
do $$
begin
  assert (select count(*) from public.reports) = 0, 'must not see other users'' reports';
end $$;
reset role;

do $$
begin
  delete from auth.users where id = '00000000-0000-0000-0000-000000000003';
  assert (select count(*) from public.reports where user_id = '00000000-0000-0000-0000-000000000003') = 0, 'reports cascade with the account';
end $$;

select 'all report tests passed' as result;
