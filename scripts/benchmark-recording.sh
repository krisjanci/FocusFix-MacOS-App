#!/bin/bash
# Synthetic histories only; no app launch, real account or saved recording access.
set -euo pipefail
cd "$(dirname "$0")/.."
benchmark_dir=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-benchmark.XXXXXX")
trap 'rm -rf -- "$benchmark_dir"' EXIT
sources=()
for name in SessionStorage DailyTimeline SessionConditions SessionTags RecordingContract ReminderEligibility StudyCheckIns ResearchArchiveContract RecordingCoverage SavedSession DailyProgress SocialProgress SocialController GroupPresentation UserProfile AccountAPI AccountController; do
    sources+=("FocusFix/FocusFix/$name.swift")
done
xcrun swiftc -O -D FOCUSFIX_SYNTHETIC_TESTS -module-cache-path "$benchmark_dir/module-cache" "${sources[@]}" Tests/RecordingEfficiencyTests.swift -o "$benchmark_dir/RecordingEfficiencyTests"
"$benchmark_dir/RecordingEfficiencyTests"
