#!/bin/bash
# Build an isolated native preview using temporary synthetic data only.
set -euo pipefail
cd "$(dirname "$0")/.."
preview_root=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-conditions-preview.XXXXXX")
preview_bundle="$preview_root/FocusFix Conditions Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
python3 - "$preview_bundle/Contents" <<'PY'
import pathlib, plistlib, sys
contents = pathlib.Path(sys.argv[1])
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.focusfix.conditions-preview',
    'CFBundleExecutable': 'ConditionsPreview',
    'CFBundleName': 'FocusFix Conditions Preview',
    'CFBundlePackageType': 'APPL',
    'NSHighResolutionCapable': True,
}))
PY
source_dir=FocusFix/FocusFix
sources=()
for name in SessionTags SessionConditions SessionConditionViews ButtonPressFeedback ButtonPressGeometry; do
    sources+=("$source_dir/$name.swift")
done
xcrun swiftc -module-cache-path "$preview_root/module-cache" "${sources[@]}" \
    verification/conditions-preview.swift -o "$preview_bundle/Contents/MacOS/ConditionsPreview"
printf '%s\n' "$preview_bundle"
