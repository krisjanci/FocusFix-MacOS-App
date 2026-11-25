#!/bin/bash
# Builds an isolated native preview using temporary synthetic project data only.
set -euo pipefail
cd "$(dirname "$0")/.."
preview_root=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-projects-preview.XXXXXX")
preview_bundle="$preview_root/FocusFix Projects Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
python3 - "$preview_bundle/Contents" <<'PY'
import pathlib, plistlib, sys
contents = pathlib.Path(sys.argv[1])
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.focusfix.projects-preview.' + contents.parents[1].name.rsplit('.', 1)[-1].lower(),
    'CFBundleExecutable': 'ProjectsPreview',
    'CFBundleName': 'FocusFix Projects Preview',
    'CFBundlePackageType': 'APPL',
    'NSHighResolutionCapable': True,
}))
PY
source_dir=FocusFix/FocusFix
sources=()
for name in SessionStorage SessionTags SessionTagViews Projects ChecklistPage ChecklistReordering ChecklistReorderRow ProjectColorChooser ProjectsView WorkAssignments RecordingContract ButtonPressFeedback ButtonPressGeometry; do
    sources+=("$source_dir/$name.swift")
done
xcrun swiftc -module-cache-path "$preview_root/module-cache" "${sources[@]}" \
    verification/projects-preview.swift -o "$preview_bundle/Contents/MacOS/ProjectsPreview"
printf '%s\n' "$preview_bundle"
