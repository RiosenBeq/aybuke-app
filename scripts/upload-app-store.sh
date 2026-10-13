#!/usr/bin/env bash
# Archives Glowlit (Release) and uploads it to App Store Connect with an
# App Store Connect API key, so Xcode needs no Apple ID signed in.
#
#   ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/upload-app-store.sh
#
# Both ids are on App Store Connect → Users and Access → Integrations →
# App Store Connect API (the Issuer ID sits above the key list). The private
# key is read from ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8; set
# ASC_KEY_PATH to use another file. Never commit the .p8 file.
#
# The app record for app.glowlit.ios must already exist in App Store Connect
# (the API can't create apps). Signing is automatic: Xcode registers the bundle
# ids, App Group and Sign in with Apple, and makes the profiles it needs, which
# takes an Admin key. The build number defaults to a timestamp such as
# 20261013.1530 so every upload is higher than the last; override it with
# BUILD_NUMBER.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

: "${ASC_KEY_ID:?Set ASC_KEY_ID to the App Store Connect API key id}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to the App Store Connect API issuer id}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$KEY_PATH" ]] || { echo "API key not found: $KEY_PATH" >&2; exit 1; }

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d).$((10#$(date +%H%M)))}"
OUT="$ROOT/build/app-store"
ARCHIVE="$OUT/Glowlit.xcarchive"
AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

rm -rf "$OUT"
mkdir -p "$OUT"

echo "Archiving build $BUILD_NUMBER…"
xcodebuild archive \
  -project "$ROOT/ios/Glowlit.xcodeproj" -scheme Glowlit -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$OUT/DerivedData" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}" -quiet

# The export only needs the archive; free the space before it runs.
rm -rf "$OUT/DerivedData"

cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>CBTKNY3LFC</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

echo "Uploading…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  "${AUTH[@]}"

echo "Uploaded Glowlit build $BUILD_NUMBER. It appears in App Store Connect → TestFlight once Apple finishes processing it (usually 10–30 minutes)."
