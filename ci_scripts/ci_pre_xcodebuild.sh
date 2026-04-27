#!/bin/sh
#
# Xcode Cloud pre-build hook.
# Runs after the repo is cloned and dependencies resolved,
# before `xcodebuild` is invoked.
#
# Substitutes Xcode Cloud's monotonic $CI_BUILD_NUMBER into
# Config.xcconfig so every Xcode Cloud build gets a unique,
# increasing build number without requiring a commit.
#
# The edit is ephemeral: Xcode Cloud uses a fresh clone per build.

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
XCCONFIG="${REPO_ROOT}/Config.xcconfig"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "CI_BUILD_NUMBER not set - refusing to bump build number" >&2
  exit 1
fi

if [ ! -f "$XCCONFIG" ]; then
  echo "Config.xcconfig not found at $XCCONFIG" >&2
  exit 1
fi

sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}/" "$XCCONFIG"

echo "=== Config.xcconfig after build-number injection ==="
cat "$XCCONFIG"
