#!/usr/bin/env bash
# Run the watch-app UI snapshot tests with a clean slate.
#
# The scheme's test pre-action erases the watch sims, but it cannot wipe
# DerivedData (xcodebuild has already opened paths inside it by the time
# pre-actions fire). When stale DerivedData is the cause of an
# "Unknown application display identifier" failure, run this script
# instead of `xcodebuild test` directly: it wipes the project's
# DerivedData first, then hands off to xcodebuild.
#
# Usage:
#   bin/run-watch-snapshot-tests.sh
#   bin/run-watch-snapshot-tests.sh -only-testing:SFTransitWatchUITests/WatchSnapshotUITests/testSnapshot_StopCodeEntry
#   RECORD_SNAPSHOTS=1 bin/run-watch-snapshot-tests.sh
#
# Any extra args are forwarded to xcodebuild.

set -euo pipefail

SCHEME="SFTransitWatch Watch App"
DESTINATION='platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
DERIVED_DATA_GLOB="${HOME}/Library/Developer/Xcode/DerivedData/SFTransitWatch-*"

echo ">> Wiping project DerivedData: ${DERIVED_DATA_GLOB}"
# shellcheck disable=SC2086
rm -rf ${DERIVED_DATA_GLOB}

EXTRA_ENV=()
if [[ "${RECORD_SNAPSHOTS:-}" == "1" ]]; then
    echo ">> RECORD_SNAPSHOTS=1 — goldens will be overwritten"
    EXTRA_ENV+=(SIMCTL_CHILD_RECORD_SNAPSHOTS=1)
fi

echo ">> xcodebuild test -scheme \"${SCHEME}\""
exec env "${EXTRA_ENV[@]}" xcodebuild test \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    "$@"
