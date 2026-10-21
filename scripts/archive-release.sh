#!/bin/bash
# Create a local signed archive only. No export, upload, notarization, commit or push.
set -euo pipefail
cd "$(dirname "$0")/.."
team_id="${1:-}"
archive_path="${2:-}"
if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ || "$archive_path" != /* || "$archive_path" != *.xcarchive ]]; then
    echo "Usage: bash scripts/archive-release.sh TEAM_ID /absolute/path/FocusFix.xcarchive" >&2
    exit 1
fi
if [[ -e "$archive_path" ]]; then echo "Choose a new archive path; existing output is preserved." >&2; exit 1; fi
# A reproducible source commit is required for distribution. Personal UI state is excluded.
if [[ -n "$(git status --porcelain --untracked-files=normal -- . ':!*.xcuserstate')" ]]; then
    echo "Archive blocked: commit the intended source changes when authorized before making a distributable archive." >&2
    exit 1
fi
revision=$(git rev-parse HEAD)
xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$team_id" FOCUSFIX_SOURCE_REVISION="$revision" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
python3 scripts/check-release-content.py "$archive_path/Products/Applications/FocusFix.app" --require-revision
echo "Local archive created. Export through Xcode Organizer using the chosen distribution method."
