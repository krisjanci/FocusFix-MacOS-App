# Preparing FocusFix for distribution

Updated October 21, 2026. This is release preparation,
**not an approved or published app**. No Apple developer signing identity is
configured on this Mac. Do not commit, push or publish without explicit authorization.

## Current build

- Production ID `io.github.krisjanci.FocusFix`; version 1.0, build 2; macOS 14 minimum.
  The archive command builds Apple Silicon and Intel. Compilation does not prove
  runtime compatibility with every advertised system.
- Both distribution paths use App Sandbox and passive Input Monitoring. No
  Accessibility permission, input injection or event modification is used for capture.
  App switches use NSWorkspace notifications. Disabled taps stop recording visibly.
- Release has hardened runtime, no debugger/network entitlement, no enrollment and
  no upload endpoint. User-selected read/write access supports explicit exports.
  Debug has its own `.debug` ID/container and permits the enrolled research receiver.
  Never distribute Debug. Research access is locked on launch; unlocking in the
  profile can restore opted-in uploads.
- The privacy manifest declares preferences (`CA92.1`) and app-container timestamps
  (`C617.1`). Empty off-device collection applies to local-only Release, not research
  builds or website hosting logs. Reassess it whenever data handling changes.
- Recording notice version 2 covers Input Monitoring, secure-input gaps, local
  storage, backups, exports, custom break labels and Trash deletion. Acceptance
  and permission alone never start recording.
- About/Help includes privacy, offline GPL text, source and public GitHub support.
  Never request recordings, credentials or private information in public Issues.

## Local verification

```sh
bash scripts/test.sh
xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/focusfix-build CODE_SIGNING_ALLOWED=NO \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
python3 scripts/check-release-content.py /tmp/focusfix-build/Build/Products/Release/FocusFix.app
```

These commands do not launch the app, request permissions, read real sessions or
upload. They cannot establish live tracking coverage or App Review acceptance.

## Signing and archiving — account required

1. Configure the Apple Developer team and register the production identifier.
   Website export requires **Developer ID Application** signing. Store export uses
   **Apple Distribution** (or the applicable Mac App Store distribution certificate)
   and a provisioning profile. Developer ID alone is not store signing.
2. After review and explicit permission to commit, create the release source commit.
   Keep certificates, keys and passwords outside Git.
3. Run `bash scripts/archive-release.sh TEAM_ID /absolute/path/FocusFix.xcarchive`.
   Replace TEAM_ID with your real ten-character identifier. This requires a clean
   source tree, records the exact source commit and creates a local signed archive.
   It never commits, pushes, exports or uploads. Personal Xcode UI state is excluded.
4. Open the archive in Xcode Organizer; choose the appropriate distribution method.
   Increment the build number before subsequent App Store uploads.

## Website export

1. Export for Developer ID/direct distribution, submit for notarization and export
   the signed app. Staple its notarization ticket.
2. Run `bash scripts/verify-release.sh /absolute/path/FocusFix.app website`.
   It checks release content, source revision, Developer ID signature, runtime,
   entitlements, stapled ticket and Gatekeeper. Never disable Gatekeeper for users.
3. Complete fresh-Mac testing below.
4. Run `bash scripts/package-website.sh /absolute/path/FocusFix.app /absolute/new/output-folder`.
   This creates an app ZIP, exact-revision source ZIP, GPL text and SHA-256 checksums.
   It never publishes. Publish all assets together only when authorized.
5. Then enable the website download button. Add install instructions, tested system
   requirements, source/license links and support/hosting privacy information. Update
   wording against the final app. The local privacy draft now describes Input Monitoring
   and sandbox storage. A repository ZIP is not an installer.

## Mac App Store export

1. Export the same Release archive with store signing and validate in Organizer.
   For an exported `.app`, run
   `bash scripts/verify-release.sh /absolute/path/FocusFix.app app-store`.
   This does not establish provisioning eligibility or Apple approval.
2. In App Store Connect, provide screenshots, description, age-rating answers,
   support/privacy URLs, copyright, export-compliance answers and review instructions.
   A review contact email is still required despite public GitHub support.
3. Verify the shipped SDK inventory and privacy answers. Current Release processes
   recordings locally and has no third-party analytics SDK. Local collection still
   requires clear disclosure and OS permission. The encryption declaration reflects
   platform services/hashing, not custom/non-exempt encryption; reassess changes.
4. Resolve GPL/store distribution rights before submission. The repository remains
   GPL-3.0-only. Build validation does not establish compatibility with Apple's terms.
   Confirm ownership of all code/artwork and a suitable distribution/EULA arrangement.
   A copyright holder can separately authorize their own material; other contributors'
   rights may require permission. No separate license or exception was silently added.
5. Test a signed sandboxed build on a fresh Mac, then TestFlight and App Review.
   Explain passive global tracking and Input Monitoring plainly to reviewers.

## Fresh-Mac qualification — still required

Test on a Mac/VM that has never granted this app permissions; cached developer
permissions are not evidence. Test macOS 14 and each advertised newer major version,
plus Intel and Apple Silicon before claiming support for both.

- Install a browser download with Gatekeeper enabled. Launch must not start recording,
  research uploads, enrollment, Keychain access or permission requests.
- Debug launch must not show Keychain prompts or resume research uploads. Explicit
  research unlock may prompt, preserves saved consent, and must read credentials only
  once per launch. Test denied Keychain access without losing local recording.
- Notice cancel/accept; the single Enable Input Monitoring button registers the app
  and opens Settings without granting access. Test denied/already-granted access,
  returning from Settings, requested quit/reopen, permission
  revocation while recording, stop/restart and duplicate Start clicks.
- In another app and FocusFix: key down/up, delete/forward-delete, hold/repeat,
  modifiers, buttons, wheel/trackpad, drag/movement and app switches. Check no duplicate
  own-window events. Use synthetic activity; exported files must not contain typed text.
- Tap interruptions stop/mark the session. Secure Input may suppress keys without
  disabling the tap: gaps are not proof of inactivity. Check reminders around password
  fields without bypassing secure input.
- Break setup must not count as outside-app return. Test automatic/explicit return,
  sleep/wake/login changes, reminders, notification denial, surveys and menu-bar actions.
- Save/relaunch, Show in Finder, sandboxed export to user-selected folders, denied
  export, filename collisions, Trash deletion, offline privacy/GPL and support links.
- Old unsandboxed sessions remain at their original Application Support location;
  export them with the old build before switching. The sandbox library starts separately.
  Do not delete old recordings, reset identities or grant full-disk access to find them.
- Release has no research controls/uploads even after an older test installation.

## Human-subject research

Ordinary local-only distribution is separate from study recruitment. Obtain the
required faculty/IRB approval, consent/enrollment, retention/deletion plan and private
participant contact channel before recruiting or collecting study data. A future
research-enabled release needs reviewed privacy declarations, network entitlements,
approved storage and end-to-end synthetic upload tests. Existing development enrollment
credentials are reusable; review before scaling. No live research data/service changed.

## Evidence and references

Oct 20: synthetic tests and an ad hoc signed universal Release build passed. Actual
Release entitlements contain only App Sandbox and user-selected read/write. Bundled
license, manifest, icon, identity, architectures and absence of the development endpoint
were checked. No developer-signed/notarized export, fresh-Mac qualification or App Store
approval is implied. See the local handoff for the current task's final verification.

- [Apple DTS: sandbox-compatible input monitoring](https://developer.apple.com/forums/thread/811443)
- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [App Review requirements](https://developer.apple.com/app-store/review/guidelines/)
- [Privacy API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [App privacy and on-device processing](https://developer.apple.com/app-store/app-privacy-details/)
- [GNU: multiple licenses](https://www.gnu.org/licenses/gpl-faq.en.html#ReleaseUnderGPLAndNF)
