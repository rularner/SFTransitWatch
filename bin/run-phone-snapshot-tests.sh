#!/usr/bin/env bash
# Run the iOS snapshot tests with a clean slate.
#
# Usage:
#   bin/run-phone-snapshot-tests.sh
#   bin/run-phone-snapshot-tests.sh -only-testing:SFTransitWatchPhoneUITests/PhoneSnapshotUITests/testSnapshot_BusStopList
#   RECORD_SNAPSHOTS=1 bin/run-phone-snapshot-tests.sh
#
# Any extra args are forwarded to xcodebuild.

set -euo pipefail

SCHEME="SFTransitWatch"
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
DERIVED_DATA_GLOB="${HOME}/Library/Developer/Xcode/DerivedData/SFTransitWatch-*"

echo ">> Wiping project DerivedData: ${DERIVED_DATA_GLOB}"
# shellcheck disable=SC2086
rm -rf ${DERIVED_DATA_GLOB}

if [[ "${RECORD_SNAPSHOTS:-}" == "1" ]]; then
    echo ">> RECORD_SNAPSHOTS=1 — goldens will be overwritten"
    export TEST_RUNNER_RECORD_SNAPSHOTS=1
fi

echo ">> xcodebuild test -scheme \"${SCHEME}\" -only-testing:SFTransitWatchPhoneUITests"
exec xcodebuild test \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -only-testing:SFTransitWatchPhoneUITests \
    "$@"
