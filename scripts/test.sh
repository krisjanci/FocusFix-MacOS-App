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
    local sources=("$source_dir/SessionTags.swift") candidate existing duplicate
    for candidate in "$source_dir/SessionTags.swift" "$source_dir/RecordingContract.swift" "$source_dir/ReminderEligibility.swift" "$source_dir/StudyCheckIns.swift" "$source_dir/ResearchArchiveContract.swift" "$source_dir/RecordingCoverage.swift" "$source_dir/SavedSession.swift" "$@"; do
        duplicate=false
        for existing in "${sources[@]}"; do if [ "$candidate" = "$existing" ]; then duplicate=true; break; fi; done
        if [ "$duplicate" = false ]; then sources+=("$candidate"); fi
    done
    xcrun swiftc -D FOCUSFIX_SYNTHETIC_TESTS -module-cache-path "$test_build_dir/module-cache" "${sources[@]}" "Tests/$name.swift" -o "$test_build_dir/$name"
    "$test_build_dir/$name"
}

run_test AutomaticRecordingPreferencesTests "$source_dir/AutomaticRecordingPreferences.swift" "$source_dir/RecordingNotice.swift" "$source_dir/LoginLaunch.swift"
run_test RecordingLifecycleTests "$source_dir/SystemIdleTime.swift" "$source_dir/RecordingLifecycle.swift" "$source_dir/SavedSession.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test ContextEditingTests "$source_dir/SavedSession.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test ReminderEligibilityTests
run_test RecordingCoverageTests "$source_dir/RecordingCoverage.swift" "$source_dir/RecordingPresentation.swift" "$source_dir/SavedSession.swift"
run_test StudyCheckInTests "$source_dir/SurveyPreferences.swift" "$source_dir/SurveyData.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/TimedCheckIn.swift"
run_test DeclaredWorkProgressTests "$source_dir/DailyProgress.swift" "$source_dir/SocialProgress.swift"
run_test ResearchArchiveContractTests "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test ExperimentalActivityPolicyTests "$source_dir/ExperimentalActivityPolicy.swift"
run_test AutomaticTrackingIntegrationTests "$source_dir/RecordingLifecycle.swift" "$source_dir/DailyProgress.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test RecordingContractTests
run_test SocialProgressTests "$source_dir/DailyProgress.swift" "$source_dir/SocialProgress.swift"
run_test SocialControllerTests "$source_dir/DailyProgress.swift" "$source_dir/SocialProgress.swift" \
    "$source_dir/SocialController.swift" "$source_dir/GroupPresentation.swift" "$source_dir/UserProfile.swift" "$source_dir/AccountAPI.swift" "$source_dir/AccountController.swift"
run_test GroupPresentationTests "$source_dir/GroupPresentation.swift" "$source_dir/SocialProgress.swift" "$source_dir/DailyProgress.swift"
run_test QuickTourTests "$source_dir/QuickTour.swift" "$source_dir/GroupPresentation.swift" "$source_dir/SocialProgress.swift" "$source_dir/DailyProgress.swift"
run_test SessionWorkPlanTests "$source_dir/SessionWorkPlan.swift" "$source_dir/SessionStartDraft.swift" "$source_dir/DailyProgress.swift"
run_test SessionRetentionTests "$source_dir/SavedSession.swift" "$source_dir/DailyProgress.swift" \
    "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift" "$source_dir/SurveyData.swift" "$source_dir/TimedCheckIn.swift"
run_test SessionTagsTests "$source_dir/SavedSession.swift"
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
run_test SurveyPreferencesTests "$source_dir/SurveyPreferences.swift" "$source_dir/SurveyData.swift" \
    "$source_dir/TimedCheckIn.swift" "$source_dir/RecordingData.swift" "$source_dir/BreakPolicy.swift"
echo "All FocusFix tests passed."
