#!/usr/bin/env bash
# Build and export a release archive for manual TestFlight upload.
#
# Usage: bin/build-testflight.sh <build-number>
#
# Check App Store Connect for the last-used build number and pass the next
# value. The number is injected at archive time without modifying Config.xcconfig.
#
# After this script finishes, open Transporter (free on the Mac App Store)
# and drag the exported .ipa to upload it to TestFlight.

set -euo pipefail

BUILD_NUMBER="${1:?Usage: bin/build-testflight.sh <build-number>}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="SFTransitWatch"
ARCHIVE_PATH="${PROJECT_ROOT}/build/SFTransitWatch.xcarchive"
EXPORT_PATH="${PROJECT_ROOT}/build/export"
EXPORT_OPTIONS="${PROJECT_ROOT}/build/ExportOptions.plist"

mkdir -p "${PROJECT_ROOT}/build"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>7W4U5RR9QZ</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

if command -v xcbeautify &>/dev/null; then
    FMT="xcbeautify"
else
    FMT="cat"
fi

echo ">> Archiving ${SCHEME} (build ${BUILD_NUMBER})…"
xcodebuild archive \
  -project "${PROJECT_ROOT}/SFTransitWatch.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  2>&1 | $FMT

echo ""
echo ">> Exporting .ipa…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  2>&1 | $FMT

IPA="$(find "$EXPORT_PATH" -name "*.ipa" | head -1)"

echo ""
echo ">> Archive: ${ARCHIVE_PATH}"
echo ">> IPA:     ${IPA}"
echo ""
echo ">> Upload via Transporter (Mac App Store): drag the .ipa in."
echo ">> Or: Xcode → Window → Organizer → Archives → Distribute App"
