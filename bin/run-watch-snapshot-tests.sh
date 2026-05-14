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
DESTINATION='platform=watchOS Simulator,name=Apple Watch SE 3 (44mm)'
DERIVED_DATA_GLOB="${HOME}/Library/Developer/Xcode/DerivedData/SFTransitWatch-*"
export RUN_UI_TESTS=1

echo ">> Wiping project DerivedData: ${DERIVED_DATA_GLOB}"
# shellcheck disable=SC2086
rm -rf ${DERIVED_DATA_GLOB}

if [[ "${RECORD_SNAPSHOTS:-}" == "1" ]]; then
    echo ">> RECORD_SNAPSHOTS=1 — goldens will be overwritten"
    # `TEST_RUNNER_<VAR>` is the documented xcodebuild knob (see `man xcodebuild`)
    # that forwards the variable into the UI test runner process with the prefix
    # stripped — i.e. RECORD_SNAPSHOTS=1 inside the test bundle.
    # `SIMCTL_CHILD_*` does not propagate to XCTRunner.app reliably, so don't use it.
    export TEST_RUNNER_RECORD_SNAPSHOTS=1
fi

echo ">> xcodebuild test -scheme \"${SCHEME}\""
exec xcodebuild test \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    "$@"
