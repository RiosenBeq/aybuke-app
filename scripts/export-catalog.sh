#!/usr/bin/env bash
# Regenerates backend/supabase/functions/_shared/catalog.json from the iOS
# template catalog (ios/Packages/AppCore). Run after editing TemplateCatalog.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$ROOT/scripts/export-catalog" -c release ExportCatalog \
  > "$ROOT/backend/supabase/functions/_shared/catalog.json"
echo "Updated backend/supabase/functions/_shared/catalog.json"
