# Getting FocusFix ready to download

## Status — October 19, 2026

Not published as an app download. I don't yet have both the Apple developer setup
and an approved study/consent plan. No valid code-signing identity was found on this
Mac. Passing the code tests doesn't mean a download is signed, notarized or ready
for participants.

## What I prepared

- Release builds are local-only: no upload endpoint, enrollment or access to the
  development Keychain/queue. An old opt-in can't silently turn uploads on.
- Debug keeps my enrolled development test. The live Worker was not changed.
- A versioned notice appears before first recording or requesting Accessibility.
  Reading it doesn't start recording or count as study consent. It's also in the profile.
- Release has hardened runtime enabled and debug base entitlements disabled.
- The website download stays disabled until I have a verified artifact.

## Before a local-only public beta

1. Get access to an Apple Developer Program team, either my own membership or an
   authorized college team. Create a **Developer ID Application** certificate.
   Don't put certificates, private keys, passwords or enrollment codes in Git.
2. Choose the permanent bundle ID in Xcode's Signing & Capabilities. It still uses
   `devplaceholder` now. Changing signing identity/bundle ID can require granting
   Accessibility again and checking Keychain access; don't reset participants' identities.
3. Decide supported Macs. The project currently targets **macOS 26.6.2**. Don't claim
   older macOS or Intel support without lowering/testing the target and verifying
   the exported architectures. No compatibility promise is based only on a build.
4. Review the privacy notice and provide a real support contact. The app collects
   sensitive interaction timing even without typed text. Explain local storage,
   backups, exports, Trash deletion and that this isn't a validated health tool.
5. Run `bash scripts/test.sh` and the upload service's synthetic tests. Build Release,
   not Debug. In Xcode: Product → Archive, then Organizer → Distribute App →
   Developer ID/direct distribution and notarization. Use the signed, notarized export.
6. Check the exact exported app:

   ```sh
   bash scripts/verify-release.sh /absolute/path/to/FocusFix.app
   ```

7. On another Mac/account, test a quarantined browser download without disabling
   Gatekeeper: launch, first-use notice/cancel, Accessibility allow/deny/revoke,
   start/stop from window and menu bar, sleep/wake, quit/relaunch, break and survey
   options, export and Trash deletion. Confirm Release has no enrollment controls,
   no research Keychain prompt and no research uploads, including on an existing
   test installation with pending uploads. Test system notification delivery too.
8. Package that exact stapled app, record its version/build, supported systems and
   SHA-256 checksum. Upload it as a versioned release asset; never upload a repository
   archive or development build as the installer. Then update the website button
   and publish the website with the privacy information and setup instructions.

I can share source without completing Apple's signing process, but that is not the
same as a normal, verified app download. I won't tell users to turn off Gatekeeper.

## Before collecting research data from other people

- Get the required IRB determination/approval and review of recruitment, consent,
  survey options and website wording with my adviser. Local-only distribution for
  ordinary personal use is distinct from recruiting people into a study.
- Agree on a retention/deletion schedule, a private participant contact channel,
  researcher access, backups and data handling. Do not invent these in a privacy policy.
- Keep enrollment per installation, revocable and private. Current credentials are
  reusable, not one-time invitations. Review onboarding before enrolling at scale.
- Test a whole synthetic session through app → receiver → private R2 → download and
  verify its files, retries, revocation and deletion process. So far the live test only
  demonstrated authentication; it wasn't a full app upload.
- Check Cloudflare account/bucket configuration and account-wide costs. Per-user
  quotas are not a guaranteed $0 cap or an account-wide abuse protection system.
- Only then deliberately change the Release upload policy, re-test, document the
  study-specific consent and publish a separately reviewed research-enabled build.

## References

- [Apple: preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Allegheny: research policies](https://allegheny.edu/academics/research/policies-guidelines-and-best-practices/)

This is a release checklist, not a complete security audit or an IRB approval.

Checked locally: ten Swift test programs (eleven runs), eight synthetic receiver
tests, unsigned Debug/Release builds, and the website's disabled button/privacy link.
The release checker rejects the current placeholder app identity as expected.
No certificate was created, no notarization was submitted, and no app was published.
