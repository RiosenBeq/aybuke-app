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
  # ${RUN_AS[@]+...}: an empty array is unbound under set -u on Bash 4.3.
  if [ "${RUN_AS[0]:-}" = "su" ]; then "${RUN_AS[@]+"${RUN_AS[@]}"}" "$*"; else "${RUN_AS[@]+"${RUN_AS[@]}"}" "$@"; fi
}
cleanup() { run "$PG_BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT

# A shell without a locale (LANG empty, as on macOS) stops initdb and the
# postmaster, so run both in the C locale with UTF-8 text.
export LC_ALL="${LC_ALL:-C}"
run "$PG_BIN/initdb" -D "$DATA" -A trust -U postgres --no-locale -E UTF8 >/dev/null
run "$PG_BIN/pg_ctl" -D "$DATA" -o "-p $PORT -k /tmp" -l "$DATA/log" start >/dev/null
for _ in $(seq 1 30); do "$PG_BIN/pg_isready" -h /tmp -p "$PORT" >/dev/null 2>&1 && break; sleep 0.5; done

PSQL=("$PG_BIN/psql" -h /tmp -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -f "$ROOT/supabase/tests/auth_stub.sql"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  "${PSQL[@]}" -f "$migration"
done
"${PSQL[@]}" -c "grant select on all tables in schema public to authenticated;"
# Every *_test.sql runs. Some suites share fixture ids and clean up after
# themselves (unclaimed before ad_rewards), so the known ones keep this order
# and any other *_test.sql runs after them.
ORDER=(credits reports accounts retry unclaimed revenuecat keepalive ad_rewards abuse)
for name in "${ORDER[@]}"; do
  "${PSQL[@]}" -f "$ROOT/supabase/tests/${name}_test.sql"
done
for test in "$ROOT"/supabase/tests/*_test.sql; do
  name="$(basename "$test" _test.sql)"
  case " ${ORDER[*]} " in *" $name "*) continue ;; esac
  "${PSQL[@]}" -f "$test"
done
