#!/bin/sh
#
# Build-phase guard for SELF_PROVISION_PRIVATE_KEY.
#
# The self-provision (store) flow signs a JWT with the P-256 key injected into
# Info.plist as $(SELF_PROVISION_PRIVATE_KEY). When that build setting is empty,
# SelfProvisionService.makeFromBundle() returns nil and the whole subscribe flow
# is silently disabled. A release archive that ships with the key missing looks
# fine in CI but has a dead store — so by default we fail the build instead.
#
# To intentionally build without the key (e.g. a fork, or a contributor without
# the secret), set ALLOW_MISSING_SELF_PROVISION_KEY = YES in Developer.xcconfig.
#
# Both values arrive as environment variables because Xcode exports every build
# setting to run-script phases. Runs standalone too, for testing:
#   SELF_PROVISION_PRIVATE_KEY= ALLOW_MISSING_SELF_PROVISION_KEY=NO bin/check-self-provision-key.sh

set -eu

if [ -n "${SELF_PROVISION_PRIVATE_KEY:-}" ]; then
  exit 0
fi

if [ "${ALLOW_MISSING_SELF_PROVISION_KEY:-NO}" = "YES" ]; then
  echo "warning: SELF_PROVISION_PRIVATE_KEY is empty; building with the self-provision/store flow disabled (ALLOW_MISSING_SELF_PROVISION_KEY=YES)"
  exit 0
fi

echo "error: SELF_PROVISION_PRIVATE_KEY is empty. The self-provision/store flow will be silently disabled in this build. Set it in Developer.xcconfig, or set ALLOW_MISSING_SELF_PROVISION_KEY = YES to build without it on purpose."
exit 1
