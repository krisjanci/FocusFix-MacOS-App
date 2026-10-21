#!/bin/bash
# Package a verified website export and the exact corresponding source; never publish.
set -euo pipefail
cd "$(dirname "$0")/.."
release_app="${1:-}"
package_dir="${2:-}"
if [[ "$package_dir" != /* || -e "$package_dir" ]]; then
    echo "Choose a new absolute output directory. Existing files will not be replaced." >&2; exit 1
fi
bash scripts/verify-release.sh "$release_app" website
revision=$(/usr/libexec/PlistBuddy -c 'Print FocusFixSourceRevision' "$release_app/Contents/Info.plist")
git cat-file -e "$revision^{commit}"
mkdir -p "$package_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_app" "$package_dir/FocusFix.zip"
# Source uses the recorded revision, never whatever happens to be in today's working tree.
git archive --format=zip --prefix=FocusFix-source/ --output="$package_dir/FocusFix-source.zip" "$revision"
cp "$release_app/Contents/Resources/GPL-3.0.txt" "$package_dir/LICENSE.txt"
printf '%s\n' "$revision" > "$package_dir/SOURCE-REVISION.txt"
(cd "$package_dir" && /usr/bin/shasum -a 256 FocusFix.zip FocusFix-source.zip LICENSE.txt SOURCE-REVISION.txt > SHA256SUMS.txt)
echo "Package created locally. Publish the app ZIP, matching source ZIP, license and checksums together only when authorized."
