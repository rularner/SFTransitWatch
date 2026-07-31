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

# Run the package's logic-test suite via `swift test` (no simulator) rather than
# relying on the "SFTransitWatch Watch App" scheme's watchOS-hosted test action,
# which hangs intermittently on Xcode Cloud's watchOS simulator ("The test runner
# hung before establishing connection." / "unknown to FrontBoard") — confirmed to
# be a CI-environment issue, not app code (same tests pass locally every time).
# Fails the whole CI action (set -e) if package logic is actually broken, same as
# a normal test-action failure would.
echo "=== Running SFTransitWatchPackage tests (swift test, no simulator) ==="
(cd "${CI_PRIMARY_REPOSITORY_PATH}/SFTransitWatchPackage" && swift test)

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

# Inject the self-provision signing key into the xcconfig from the Xcode Cloud
# environment variable. This is REQUIRED, not optional: Info.plist substitutes
# $(SELF_PROVISION_PRIVATE_KEY) from *build settings*, and Xcode Cloud
# environment variables are NOT promoted to build settings (same reason
# CI_BUILD_NUMBER is sed'd in above). Setting the env var alone would let the
# build-phase guard (bin/check-self-provision-key.sh) pass — it reads the
# inherited shell env — while the shipped app still got an empty key. Append
# (don't sed) because the value is base64 and contains '/' and '+'; appended
# after the #include? line it's the only definition in CI (Developer.xcconfig
# is gitignored and absent). If the env var is unset, leave it empty and let
# the build-phase guard fail the build with its explanatory message.
if [ -n "${SELF_PROVISION_PRIVATE_KEY:-}" ]; then
  printf '\nSELF_PROVISION_PRIVATE_KEY = %s\n' "$SELF_PROVISION_PRIVATE_KEY" >> "$XCCONFIG"
  echo "Injected SELF_PROVISION_PRIVATE_KEY from Xcode Cloud environment"
else
  echo "SELF_PROVISION_PRIVATE_KEY not set in environment; build-phase guard will decide whether to fail"
fi

# Keep CFBundleShortVersionString aligned with release tags in CI.
# If tags are available, use the latest semver tag (vX.Y.Z) as MARKETING_VERSION.
# Instead of a simple fetch, get all history and tags
git fetch --unshallow --tags origin || git fetch --tags origin

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
