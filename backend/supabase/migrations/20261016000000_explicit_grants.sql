-- Explicit privileges, so the schema works on projects created with
-- "Automatically expose new tables" turned off (Supabase's recommended
-- setting). The Edge Functions use the service role; clients only ever read
-- their own rows through RLS, and every write goes through the functions.
grant usage on schema public to service_role, authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant select on all tables in schema public to authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
