#!/usr/bin/env bash
# Runs the migration + ledger tests on a throwaway local PostgreSQL (14+).
# Usage: backend/scripts/test-db.sh   (needs initdb/pg_ctl/psql on PATH or PG_BIN)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls /usr/lib/postgresql/*/bin/initdb | sort -V | tail -1)")}"
DATA="$(mktemp -d)"
PORT="${PGPORT_TEST:-55432}"
RUN_AS=()
if [ "$(id -u)" = "0" ]; then
  chown postgres "$DATA"
  RUN_AS=(sudo -u postgres)
  command -v sudo >/dev/null || RUN_AS=(su postgres -s /bin/bash -c)
fi
run() {
  if [ "${RUN_AS[0]:-}" = "su" ]; then "${RUN_AS[@]}" "$*"; else "${RUN_AS[@]}" "$@"; fi
}
cleanup() { run "$PG_BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT

run "$PG_BIN/initdb" -D "$DATA" -A trust -U postgres >/dev/null
run "$PG_BIN/pg_ctl" -D "$DATA" -o "-p $PORT -k /tmp" -l "$DATA/log" start >/dev/null
for _ in $(seq 1 30); do "$PG_BIN/pg_isready" -h /tmp -p "$PORT" >/dev/null 2>&1 && break; sleep 0.5; done

PSQL=("$PG_BIN/psql" -h /tmp -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -f "$ROOT/supabase/tests/auth_stub.sql"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  "${PSQL[@]}" -f "$migration"
done
"${PSQL[@]}" -c "grant select on all tables in schema public to authenticated;"
for test in credits reports accounts retry unclaimed; do
  test="$ROOT/supabase/tests/${test}_test.sql"
  "${PSQL[@]}" -f "$test"
done
