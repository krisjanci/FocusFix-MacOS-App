#!/bin/bash
# FF: RELEASE — read-only checks on the exact exported app, not permission bypasses.
# Run with: bash scripts/verify-release.sh /absolute/path/to/FocusFix.app
set -euo pipefail
release_app="${1:-}"
if [[ "$release_app" != /* || "$release_app" != *.app || ! -d "$release_app/Contents" ]]; then
    echo "Pass an absolute path to the exported FocusFix.app." >&2
    exit 1
fi

# Refuse development/placeholder builds before any download can be considered ready.
release_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$release_app/Contents/Info.plist")
if [[ "$release_id" == devplaceholder.* ]]; then
    echo "Not ready: choose and register a stable bundle identifier for distribution." >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$release_app"
release_signature=$(/usr/bin/codesign --display --verbose=4 "$release_app" 2>&1)
if [[ "$release_signature" != *"Authority=Developer ID Application:"* || "$release_signature" != *"Timestamp="* ]] ||
   ! /usr/bin/grep -Eq '^CodeDirectory .*flags=.*runtime' <<< "$release_signature"; then
    echo "Not ready: Developer ID signing, hardened runtime and a secure timestamp are required." >&2
    exit 1
fi

release_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-release-check.XXXXXX")
trap 'rm -rf -- "$release_check_dir"' EXIT
/usr/bin/codesign --display --entitlements - --xml "$release_app" > "$release_check_dir/entitlements.plist" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print com.apple.security.get-task-allow' "$release_check_dir/entitlements.plist" 2>/dev/null | /usr/bin/grep -q true; then
    echo "Not ready: the exported app still allows debugger attachment." >&2
    exit 1
fi

# A stapled notarization ticket and Gatekeeper acceptance are required for this release process.
/usr/bin/xcrun stapler validate "$release_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$release_app"
echo "Signature, notarization ticket and Gatekeeper checks passed."
echo "Still complete the manual privacy, recording and clean-Mac checks in RELEASE.md."
