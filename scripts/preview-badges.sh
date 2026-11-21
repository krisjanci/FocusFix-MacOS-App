#!/bin/bash
# Builds a separate native preview. It never links the real tracker or account client.
set -euo pipefail
cd "$(dirname "$0")/.."
preview_root=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-badge-preview.XXXXXX")
preview_bundle="$preview_root/FocusFix Badge Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
python3 - "$preview_bundle/Contents" "$@" <<'PY'
import pathlib, plistlib, sys
contents = pathlib.Path(sys.argv[1])
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.focusfix.badge-preview',
    'CFBundleExecutable': 'BadgePreview',
    'CFBundleName': 'FocusFix Badge Preview',
    'CFBundlePackageType': 'APPL',
    'NSHighResolutionCapable': True,
    'BadgePreviewOptions': sys.argv[2:],
}))
PY
source_dir=FocusFix/FocusFix
sources=()
for name in SessionConditions SessionTags RecordingContract ReminderEligibility StudyCheckIns ResearchArchiveContract RecordingCoverage SavedSession DailyProgress Badges BadgeController BadgeArtwork LaunchScreen BadgeSharing BadgeCelebration BadgeKeyboard AnalyticsPanel ButtonPressFeedback ButtonPressGeometry; do
    sources+=("$source_dir/$name.swift")
done
xcrun swiftc -module-cache-path "$preview_root/module-cache" "${sources[@]}" \
    Tests/BadgeTestSupport.swift verification/badge-preview.swift -o "$preview_bundle/Contents/MacOS/BadgePreview"
printf '%s\n' "$preview_bundle"
