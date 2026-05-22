#!/usr/bin/env bash
# Build and upload a release archive to TestFlight.
#
# Usage: bin/build-testflight.sh
#
# Run bin/prep-manual-build.sh first to stamp Developer.xcconfig with the
# correct build number and marketing version. This script reads
# CURRENT_PROJECT_VERSION from that file.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_XCCONFIG="${PROJECT_ROOT}/Developer.xcconfig"

BUILD_NUMBER="$(grep '^CURRENT_PROJECT_VERSION' "$DEV_XCCONFIG" | tail -1 | sed 's/.*= *//')"
if [[ -z "$BUILD_NUMBER" ]]; then
    echo "error: CURRENT_PROJECT_VERSION not found in Developer.xcconfig — run bin/prep-manual-build.sh first" >&2
    exit 1
fi
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
    <string>upload</string>
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
  -allowProvisioningUpdates \
  2>&1 | $FMT

echo ""
echo ">> Archive: ${ARCHIVE_PATH}"
echo ">> Upload complete — check App Store Connect / TestFlight for the build."
