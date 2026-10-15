#!/usr/bin/env bash
# Archives Aybuke (Release) and uploads it to App Store Connect with an
# App Store Connect API key, so Xcode needs no Apple ID signed in.
#
#   ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/upload-app-store.sh
#   PLATFORM=mac ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/upload-app-store.sh
#
# Capabilities the app id needs (automatic signing registers them): App
# Groups, Sign in with Apple and Declared Age Range.
#
# PLATFORM=mac uploads the Mac app (Mac Catalyst) to the same app record; the
# record needs the macOS platform added first (see
# docs/marketing/app-store-connect-setup.md).
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
# BUILD_NUMBER. scripts/check-release-config.py runs first and stops the
# upload on release blockers (GL_PREVIEW_BUILD=1 for a preview build).
#
# SIGNING=account signs and uploads with the Apple Account signed in to Xcode
# (Xcode › Settings › Accounts) instead of the API key. Use it when the key
# can't provision: on 15 October 2026 xcodebuild answered "Authentication
# failed" for an Admin team key that altool and the API accepted, so it
# couldn't register the widget's bundle id or the App Group.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING="${SIGNING:-key}"

if [[ "$SIGNING" != account ]]; then
  : "${ASC_KEY_ID:?Set ASC_KEY_ID to the App Store Connect API key id}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to the App Store Connect API issuer id}"
  KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  [[ -f "$KEY_PATH" ]] || { echo "API key not found: $KEY_PATH" >&2; exit 1; }
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d).$((10#$(date +%H%M)))}"
PLATFORM="${PLATFORM:-ios}"
case "$PLATFORM" in
  ios) DESTINATION='generic/platform=iOS'; OUT="$ROOT/build/app-store" ;;
  mac) DESTINATION='generic/platform=macOS,variant=Mac Catalyst'; OUT="$ROOT/build/app-store-mac" ;;
  *) echo "PLATFORM must be ios or mac" >&2; exit 1 ;;
esac
ARCHIVE="$OUT/Glowlit.xcarchive"

# Release blockers: demo mode, legal placeholders, dead website or mail
# domains. For a deliberate preview upload (TestFlight before Supabase and
# the company details exist) set GL_PREVIEW_BUILD=1, and never submit that
# build for review.
python3 "$ROOT/scripts/check-release-config.py" --online
AUTH=(-allowProvisioningUpdates)
if [[ "$SIGNING" != account ]]; then
  AUTH+=(
    -authenticationKeyPath "$KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "Archiving $PLATFORM build $BUILD_NUMBER…"
xcodebuild archive \
  -project "$ROOT/ios/Glowlit.xcodeproj" -scheme Glowlit -configuration Release \
  -destination "$DESTINATION" \
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

echo "Uploaded Aybuke $PLATFORM build $BUILD_NUMBER. It appears in App Store Connect → TestFlight once Apple finishes processing it (usually 10–30 minutes)."
