#!/usr/bin/env bash
# Stamp Developer.xcconfig with the correct versions before a manual TestFlight
# archive via Xcode GUI (Product → Archive → Distribute App).
#
# Usage: bin/prep-manual-build.sh
#
# MARKETING_VERSION is derived from the latest v* git tag.
# CURRENT_PROJECT_VERSION is read from Developer.xcconfig and incremented by 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_XCCONFIG="${SCRIPT_DIR}/../Developer.xcconfig"

CURRENT_BUILD="$(grep '^CURRENT_PROJECT_VERSION' "$DEV_XCCONFIG" | tail -1 | sed 's/.*= *//')"
if [[ -z "$CURRENT_BUILD" ]]; then
    echo "error: CURRENT_PROJECT_VERSION not found in Developer.xcconfig" >&2
    exit 1
fi
BUILD_NUMBER=$(( CURRENT_BUILD + 1 ))

LATEST_TAG="$(git tag -l 'v*' --sort=-v:refname | head -1)"
if [[ -z "$LATEST_TAG" ]]; then
    echo "error: no v* tags found; commit and tag a release first" >&2
    exit 1
fi
MARKETING_VERSION="${LATEST_TAG#v}"

# Rewrite only the two version lines, leaving everything else intact
sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${MARKETING_VERSION}/" "$DEV_XCCONFIG"
sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/" "$DEV_XCCONFIG"

echo "Developer.xcconfig updated:"
echo "  MARKETING_VERSION     = ${MARKETING_VERSION}"
echo "  CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}"
echo ""
echo "Now: Product → Archive in Xcode, then Distribute App → TestFlight & App Store."
