#!/bin/sh
#
# Build-phase guard for SELF_PROVISION_PRIVATE_KEY.
#
# The self-provision (store) flow signs a JWT with the P-256 key injected into
# Info.plist as $(SELF_PROVISION_PRIVATE_KEY). When that resolves to empty,
# SelfProvisionService.makeFromBundle() returns nil and the whole subscribe flow
# is silently disabled. A release archive that ships with the key missing looks
# fine but has a dead store — so by default we fail the build instead.
#
# We read the *processed* Info.plist from the built bundle, NOT the
# $SELF_PROVISION_PRIVATE_KEY shell variable. The shell variable is an unreliable
# signal: in Xcode Cloud the key is a workflow environment variable, which is
# inherited into this script's process environment even when it was never
# promoted to a build setting (and so never substituted into Info.plist). Reading
# the resolved plist value — the exact bytes that ship — avoids that false
# positive. It does mean this guard runs late, after "Process Info.plist"; the
# build phase declares the plist as an input so the build system orders it after
# plist processing.
#
# To intentionally build without the key (e.g. a fork, or a contributor without
# the secret), set ALLOW_MISSING_SELF_PROVISION_KEY = YES in Developer.xcconfig.
#
# Standalone testing: point INFO_PLIST at a plist and run directly:
#   INFO_PLIST=/tmp/x.plist ALLOW_MISSING_SELF_PROVISION_KEY=NO bin/check-self-provision-key.sh

set -eu

PLIST="${INFO_PLIST:-${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}}"

if [ -z "$PLIST" ] || [ ! -f "$PLIST" ]; then
  echo "error: check-self-provision-key.sh could not locate the processed Info.plist (looked at '${PLIST}'). This guard must run after the Process Info.plist build step."
  exit 1
fi

KEY="$(/usr/libexec/PlistBuddy -c 'Print :SELF_PROVISION_PRIVATE_KEY' "$PLIST" 2>/dev/null || true)"

if [ -n "$KEY" ]; then
  exit 0
fi

if [ "${ALLOW_MISSING_SELF_PROVISION_KEY:-NO}" = "YES" ]; then
  echo "warning: SELF_PROVISION_PRIVATE_KEY is empty in the built Info.plist; building with the self-provision/store flow disabled (ALLOW_MISSING_SELF_PROVISION_KEY=YES)"
  exit 0
fi

echo "error: SELF_PROVISION_PRIVATE_KEY is empty in the built Info.plist. The self-provision/store flow will be silently disabled in this build. Set it in Developer.xcconfig (or, for Xcode Cloud, the workflow environment plus the ci_post_clone.sh injection), or set ALLOW_MISSING_SELF_PROVISION_KEY = YES to build without it on purpose."
exit 1
