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

SCHEME="SFTransitWatchPhoneSnapshots"
DESTINATION='platform=iOS Simulator,OS=26.4.1,name=iPhone 17 Pro'
DERIVED_DATA_GLOB="${HOME}/Library/Developer/Xcode/DerivedData/SFTransitWatch-*"

echo ">> Wiping project DerivedData: ${DERIVED_DATA_GLOB}"
# shellcheck disable=SC2086
rm -rf ${DERIVED_DATA_GLOB}

if [[ "${RECORD_SNAPSHOTS:-}" == "1" ]]; then
    echo ">> RECORD_SNAPSHOTS=1 — goldens will be overwritten"
    export TEST_RUNNER_RECORD_SNAPSHOTS=1
fi

echo ">> xcodebuild test -scheme \"${SCHEME}\""
ARGS=(-scheme "${SCHEME}" -destination "${DESTINATION}")

xcodebuild test "${ARGS[@]}" "$@"

if [[ "${RECORD_SNAPSHOTS:-}" == "1" ]]; then
    echo ">> Resizing golden snapshots to App Store compliant 1284x2778"
    GOLDENS_DIR="SFTransitWatchPhoneUITests/Goldens"
    for png in "${GOLDENS_DIR}"/*.png; do
        if [[ -f "$png" ]]; then
            echo "   Resizing $(basename "$png")"
            sips -z 2778 1284 "$png" --out "$png"
        fi
    done
fi

for f in SFTransitWatchPhoneUITests/Goldens/*.png; do
  sips -z 2688 1242 "$f"
done
