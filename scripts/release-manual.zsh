#!/bin/zsh
# Archive, export and upload Aybuke with manual signing and altool (no Xcode account needed).
#   PLATFORMS="ios mac" REPO=<clean worktree of the commit to ship> scripts/release-manual.zsh
# Why manual: automatic signing can't make profiles with the API key, and a locked keychain of
# another project holds the first "Apple Distribution" identity (AGENTS.md §6 item 2).
# It stops before archiving when an App Store profile isn't ACTIVE at Apple: an App ID change
# invalidates profiles, and TestFlight then can't install builds signed with them.
set -u
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
cd $REPO || exit 1
mkdir -p build/logs
LOG=$REPO/build/logs/release-manual.log
: > $LOG
set -a; source ~/.config/aybuke/asc.env; set +a
CERT=37B98E477C368F2436FE935575D85BD0905E4882           # Apple Distribution Y3J8PJTG6G (login keychain)
INSTALLER=302DAACBB391519EA07295B476DA11D0E0DF9F6B      # Mac Installer Distribution 53MJGDC4PC
PYTHONPATH=$REPO/scripts/asc ~/.venvs/aybuke/bin/python -W ignore - >> $LOG 2>&1 <<'PY' || { echo "PROFILES NOT ACTIVE" | tee -a $LOG; exit 1; }
import sys, asc
need = {"Aybuke App Store 2", "Aybuke Widgets App Store", "Aybuke Mac Catalyst App Store 2", "Aybuke Widgets Mac Catalyst App Store"}
state = {p["attributes"]["name"]: p["attributes"]["profileState"] for p in asc.get("/v1/profiles", limit=100)["data"]}
bad = {n: state.get(n, "MISSING") for n in need if state.get(n) != "ACTIVE"}
print("profiles ACTIVE" if not bad else f"profiles not usable: {bad}")
sys.exit(1 if bad else 0)
PY
for PLATFORM in ${=${PLATFORMS:-ios mac}}; do
  if [[ $PLATFORM == ios ]]; then
    OUT=build/app-store; TYPE=ios; DEST='generic/platform=iOS'
    P1="Aybuke App Store 2"; P2="Aybuke Widgets App Store"
    U1=4ee1d304-e5f0-4bd0-8637-cf78076f2fe2; U2=e0a288b9-d6c0-47e6-9a2e-9faf898edcad; INST=""
  else
    OUT=build/app-store-mac; TYPE=macos; DEST='generic/platform=macOS,variant=Mac Catalyst'
    P1="Aybuke Mac Catalyst App Store 2"; P2="Aybuke Widgets Mac Catalyst App Store"
    U1=eeddb0f7-99fd-4700-8c6b-11e89bbf86b5; U2=c8af9c11-e005-461d-97e0-5af2c972ca68
    INST="<key>installerSigningCertificate</key><string>$INSTALLER</string>"
  fi
  rm -rf $OUT && mkdir -p $OUT
  BN=$(date +%Y%m%d).$((10#$(date +%H%M)))
  echo "[$(date +%H:%M:%S)] $PLATFORM archive build $BN" >> $LOG
  xcodebuild archive -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release \
    -destination "$DEST" -archivePath $OUT/Glowlit.xcarchive -derivedDataPath $OUT/DerivedData \
    CURRENT_PROJECT_VERSION=$BN CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=CBTKNY3LFC CODE_SIGN_IDENTITY=$CERT \
    'PROVISIONING_PROFILE_SPECIFIER=$(GL_PROFILE_$(TARGET_NAME))' "GL_PROFILE_Glowlit=$P1" "GL_PROFILE_GlowlitWidgetsExtension=$P2" \
    -quiet >> $LOG 2>&1 || { echo "ARCHIVE FAILED $PLATFORM" | tee -a $LOG; exit 1; }
  rm -rf $OUT/DerivedData
  cat > $OUT/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>teamID</key><string>CBTKNY3LFC</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>$CERT</string>
$INST
<key>provisioningProfiles</key><dict>
<key>app.glowlit.ios</key><string>$U1</string>
<key>app.glowlit.ios.widgets</key><string>$U2</string>
</dict>
<key>uploadSymbols</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
  echo "[$(date +%H:%M:%S)] $PLATFORM export" >> $LOG
  xcodebuild -exportArchive -archivePath $OUT/Glowlit.xcarchive -exportOptionsPlist $OUT/ExportOptions.plist \
    -exportPath $OUT/export >> $LOG 2>&1 || { echo "EXPORT FAILED $PLATFORM" | tee -a $LOG; exit 1; }
  PKG=$(find $OUT/export -maxdepth 1 \( -name '*.ipa' -o -name '*.pkg' \) | head -1)
  [[ -n $PKG ]] || { echo "NO PACKAGE $PLATFORM" | tee -a $LOG; exit 1; }
  echo "[$(date +%H:%M:%S)] $PLATFORM upload $(basename $PKG) build $BN" >> $LOG
  # altool can report "Redundant Binary Upload" on its own retry after a first attempt went through.
  xcrun altool --upload-app --type $TYPE --file "$PKG" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" >> $LOG 2>&1 \
    || grep -q "Redundant Binary Upload" $LOG || { echo "UPLOAD FAILED $PLATFORM" | tee -a $LOG; exit 1; }
  echo "UPLOADED $PLATFORM $BN" | tee -a $LOG
  rm -rf $OUT/Glowlit.xcarchive
done
echo "RELEASE DONE" | tee -a $LOG
