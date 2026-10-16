#!/usr/bin/env bash
# Regenerates backend/supabase/functions/_shared/catalog.json and policy-terms.json
# from ios/Packages/AppCore. Run after editing TemplateCatalog.swift, StyleCatalog.swift,
# MakeupStudio.swift (catalog.json's "makeup": ids the assist function may answer), Enhance.swift
# ("enhanceModes": the instructions ai-image sends for each Enhance mode) or ContentPolicy.swift.
# Both files are written to temporary files and moved into place only after both
# builds succeed, so a failed build never leaves an empty or half-written file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/backend/supabase/functions/_shared"
CATALOG_TMP="$SHARED/catalog.json.tmp"
POLICY_TMP="$SHARED/policy-terms.json.tmp"
trap 'rm -f "$CATALOG_TMP" "$POLICY_TMP"' EXIT
swift run --package-path "$ROOT/scripts/export-catalog" -c release ExportCatalog > "$CATALOG_TMP"
swift run --package-path "$ROOT/scripts/export-catalog" -c release ExportCatalog --policy > "$POLICY_TMP"
mv "$CATALOG_TMP" "$SHARED/catalog.json"
mv "$POLICY_TMP" "$SHARED/policy-terms.json"
echo "Updated backend/supabase/functions/_shared/catalog.json and policy-terms.json"
