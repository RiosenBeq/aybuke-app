-- Row level security on every table in the private schema (install salt,
-- installs, strikes, cool-downs, blocks, IP and daily AI counts).
-- ----------------------------------------------------------------------------
-- Access is already closed by the schema (no usage granted to any API role) and
-- by revoked table privileges. RLS is defence in depth: with it on and no
-- policy, a client role that somehow got a grant still reads no row. No policy
-- is added. The SECURITY DEFINER functions are owned by postgres, the table
-- owner, and bypass RLS, which is why they keep working.

alter table private.install_salt enable row level security;
alter table private.app_installs enable row level security;
alter table private.ai_usage_daily enable row level security;
alter table private.ip_usage enable row level security;
alter table private.strikes enable row level security;
alter table private.cooldowns enable row level security;
alter table private.blocks enable row level security;
alter table private.ai_switches enable row level security;
