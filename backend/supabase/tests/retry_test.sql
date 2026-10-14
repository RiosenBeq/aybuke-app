-- Likeness Lock free retry. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000004');

-- A free retry that times out gives the retry back; a finished one doesn't.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000004';
  original uuid := gen_random_uuid();
  stuck uuid := gen_random_uuid();
  done uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, status, retried, created_at)
    values (original, u, 'magic_edit', 'test', 1, 'completed', true, now() - interval '20 minutes'),
           (other, u, 'magic_edit', 'test', 1, 'completed', true, now() - interval '20 minutes');
  insert into public.jobs (id, user_id, operation, endpoint, cost, status, retry_of, created_at)
    values (stuck, u, 'magic_edit', 'test', 0, 'processing', original, now() - interval '16 minutes'),
           (done, u, 'magic_edit', 'test', 0, 'completed', other, now() - interval '16 minutes');
  perform public.sweep_jobs();
  assert (select status from public.jobs where id = stuck) = 'failed', 'stuck retry times out';
  assert (select retried from public.jobs where id = original) = false, 'a timed-out retry can be retried again';
  assert (select retried from public.jobs where id = other) = true, 'a finished retry stays used';
end $$;

delete from auth.users where id = '00000000-0000-0000-0000-000000000004';

select 'all retry tests passed' as result;
