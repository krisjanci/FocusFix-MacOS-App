#!/bin/bash
# FF: RELEASE — read-only checks on the exact exported app, not permission bypasses.
# Run with: bash scripts/verify-release.sh /absolute/path/to/FocusFix.app [website|app-store]
set -euo pipefail
release_app="${1:-}"
release_mode="${2:-website}"
if [[ "$release_mode" != website && "$release_mode" != app-store ]]; then
    echo "Choose website or app-store." >&2; exit 1
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
if [[ "$release_app" != /* || "$release_app" != *.app || ! -d "$release_app/Contents" ]]; then
    echo "Pass an absolute path to the exported FocusFix.app." >&2
    exit 1
fi

release_content_args=(--require-revision)
if [[ "$release_mode" == app-store ]]; then release_content_args+=(--submission-ready); fi
python3 "$script_dir/check-release-content.py" "$release_app" "${release_content_args[@]}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$release_app"
release_signature=$(/usr/bin/codesign --display --verbose=4 "$release_app" 2>&1)
if [[ "$release_mode" == website ]]; then
    if [[ "$release_signature" != *"Authority=Developer ID Application:"* || "$release_signature" != *"Timestamp="* ]] ||
       ! /usr/bin/grep -Eq '^CodeDirectory .*flags=.*runtime' <<< "$release_signature"; then
        echo "Not ready: Developer ID signing, hardened runtime and a secure timestamp are required." >&2
        exit 1
    fi
else
    if [[ "$release_signature" != *"Authority=Apple Distribution:"* && "$release_signature" != *"Authority=3rd Party Mac Developer Application:"* ]]; then
        echo "Not ready: export with Mac App Store distribution signing." >&2; exit 1
    fi
    if [[ ! -f "$release_app/Contents/embedded.provisionprofile" ]]; then
        echo "Not ready: missing Mac App Store provisioning profile." >&2; exit 1
    fi
fi

release_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/focusfix-release-check.XXXXXX")
trap 'rm -rf -- "$release_check_dir"' EXIT
/usr/bin/codesign --display --entitlements - --xml "$release_app" > "$release_check_dir/entitlements.plist" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print com.apple.security.get-task-allow' "$release_check_dir/entitlements.plist" 2>/dev/null | /usr/bin/grep -q true; then
    echo "Not ready: the exported app still allows debugger attachment." >&2
    exit 1
fi

python3 - "$release_check_dir/entitlements.plist" "$release_app/Contents/Info.plist" <<'CHECK'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    entitlements = plistlib.load(stream)
required = {'com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-write'}
if not all(entitlements.get(key) is True for key in required):
    sys.exit('Not ready: sandbox and user-selected export access required')
with open(sys.argv[2], 'rb') as stream:
    info = plistlib.load(stream)
if info.get('FocusFixAccountURL'):
    required.add('com.apple.security.network.client')
    if entitlements.get('com.apple.security.network.client') is not True:
        sys.exit('Not ready: configured accounts require outgoing network access')
for key, value in entitlements.items():
    if key.startswith('com.apple.security.') and key not in required:
        if value is not False:
            sys.exit(f'Not ready: unexpected Release entitlement: {key}')
CHECK

if [[ "$release_mode" == website ]]; then
    /usr/bin/xcrun stapler validate "$release_app"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$release_app"
    echo "Website signature, entitlements, notarization ticket and Gatekeeper checks passed."
else
    echo "Store signature, entitlements and content checks passed; validate/upload through App Store Connect next."
    echo "This does not verify provisioning eligibility or constitute App Review approval."
fi
echo "Still complete the clean-Mac, privacy and licensing checks in RELEASE.md."
