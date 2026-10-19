#!/bin/bash
# Synthetic data only. This never opens the app or reads saved participant sessions.
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-tests.XXXXXX")
trap 'rm -rf -- "$test_build_dir"' EXIT
source_dir="FocusFix/FocusFix"

run_test() {
    local name="$1"
    shift
    echo "Testing $name"
    xcrun swiftc -module-cache-path "$test_build_dir/module-cache" \
        "$@" "Tests/$name.swift" -o "$test_build_dir/$name"
    "$test_build_dir/$name"
}

run_test RecordingDataTests "$source_dir/RecordingData.swift" \
    "$source_dir/BreakPolicy.swift" "$source_dir/SavedSession.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test BreakPolicyTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test SurveyDataTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test TimedCheckInTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test NotificationAccessTests "$source_dir/NotificationAccess.swift"
echo "All FocusFix tests passed."
