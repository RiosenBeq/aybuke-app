#!/usr/bin/env bash
# Regenerates backend/supabase/functions/_shared/catalog.json and policy-terms.json
# from ios/Packages/AppCore. Run after editing TemplateCatalog.swift or ContentPolicy.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$ROOT/scripts/export-catalog" -c release ExportCatalog \
  > "$ROOT/backend/supabase/functions/_shared/catalog.json"
swift run --package-path "$ROOT/scripts/export-catalog" -c release ExportCatalog --policy \
  > "$ROOT/backend/supabase/functions/_shared/policy-terms.json"
echo "Updated backend/supabase/functions/_shared/catalog.json and policy-terms.json"
