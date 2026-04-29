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

# In test-only workflows Xcode Cloud only checks out ci_scripts/, not the full
# source — so CI_PRIMARY_REPOSITORY_PATH is unset and there's nothing to patch.
if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  echo "ci_pre_xcodebuild: no source checkout (test-only workflow); skipping build-number injection"
  exit 0
fi

XCCONFIG="${CI_PRIMARY_REPOSITORY_PATH}/Config.xcconfig"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "CI_BUILD_NUMBER not set - refusing to bump build number" >&2
  exit 1
fi

if [ ! -f "$XCCONFIG" ]; then
  echo "Config.xcconfig not found at $XCCONFIG" >&2
  exit 1
fi

sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}/" "$XCCONFIG"

# Keep CFBundleShortVersionString aligned with release tags in CI.
# If tags are available, use the latest semver tag (vX.Y.Z) as MARKETING_VERSION.
if git -C "$CI_PRIMARY_REPOSITORY_PATH" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$CI_PRIMARY_REPOSITORY_PATH" fetch --tags origin >/dev/null 2>&1 || true
  LATEST_TAG="$(git -C "$CI_PRIMARY_REPOSITORY_PATH" tag -l 'v*' --sort=-v:refname | head -n 1)"
  if [ -n "$LATEST_TAG" ]; then
    TAG_VERSION="${LATEST_TAG#v}"
    if echo "$TAG_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${TAG_VERSION}/" "$XCCONFIG"
      echo "Set MARKETING_VERSION from latest tag: ${LATEST_TAG}"
    else
      echo "Latest tag '${LATEST_TAG}' is not semver; leaving MARKETING_VERSION unchanged"
    fi
  else
    echo "No v* tags found; leaving MARKETING_VERSION unchanged"
  fi
fi

echo "=== Config.xcconfig after build-number injection ==="
cat "$XCCONFIG"
