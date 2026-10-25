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

run_test SessionWorkPlanTests "$source_dir/SessionWorkPlan.swift" "$source_dir/SessionWorkPlanPreferences.swift" "$source_dir/DailyProgress.swift"
run_test LaunchCoordinatorTests "$source_dir/UserProfile.swift" "$source_dir/AccountAPI.swift" \
    "$source_dir/AccountController.swift" "$source_dir/LaunchCoordinator.swift"
run_test AccountTests "$source_dir/UserProfile.swift" "$source_dir/AccountAPI.swift" "$source_dir/AccountController.swift"
run_test ResearchDeliveryTests "$source_dir/UserProfile.swift" "$source_dir/AccountAPI.swift" "$source_dir/AccountController.swift" \
    "$source_dir/ResearchSharing.swift" "$source_dir/ResearchSharingController.swift" "$source_dir/SavedSession.swift"
run_test ResearchSharingTests "$source_dir/UserProfile.swift" "$source_dir/AccountAPI.swift" "$source_dir/ResearchSharing.swift"
run_test UserProfileTests "$source_dir/UserProfile.swift" "$source_dir/ProfileController.swift"
run_test DailyProgressTests "$source_dir/DailyProgress.swift" "$source_dir/BreakPolicy.swift" \
    "$source_dir/RecordingData.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test RecordingDataTests "$source_dir/RecordingData.swift" \
    "$source_dir/BreakPolicy.swift" "$source_dir/SavedSession.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test BreakPolicyTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test SurveyDataTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test TimedCheckInTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test NotificationAccessTests "$source_dir/NotificationAccess.swift"
run_test RecordingNoticeTests "$source_dir/RecordingNotice.swift"
run_test InputMonitorTests "$source_dir/InputMonitor.swift"
run_test ReleaseConfigurationTests "$source_dir/UploadPolicy.swift" "$source_dir/UploadTransport.swift"
run_test ReleaseConfigurationTests -D DEBUG "$source_dir/UploadPolicy.swift" "$source_dir/UploadTransport.swift"
run_test SurveyPreferencesTests "$source_dir/SurveyPreferences.swift" "$source_dir/SurveyData.swift" \
    "$source_dir/TimedCheckIn.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift"
run_test UploadPolicyTests "$source_dir/UploadPolicy.swift" "$source_dir/UploadTransport.swift"
run_test SharingQueueTests "$source_dir/UploadPolicy.swift" "$source_dir/UploadTransport.swift" \
    "$source_dir/SharingController.swift" "$source_dir/SharingEnvironment.swift" \
    "$source_dir/SharingIdentity.swift" "$source_dir/SavedSession.swift"
echo "All FocusFix tests passed."
