# FocusFix Mac App Store submission package

Updated November 2, 2026. Draft materials and verification instructions, not a
submitted/approved app. No Apple agreement, license exception or rights assignment
is accepted or created by this implementation.

## Listing copy

**Name:** FocusFix (availability to be checked in App Store Connect)

**Subtitle:** Activity patterns and breaks

**Category:** Productivity. **Minimum target:** macOS 14; verify actual supported
OS/hardware combinations before advertising them. **Bundle ID:** io.github.krisjanci.FocusFix.

**Description:**

FocusFix records local computer-use patterns with optional user-declared work labels
and fixed timer/idle break reminders. Start work manually, or separately opt into
automatic recording while the app runs, including non-work use. Automatic activity
starts Unknown. Work declarations and recorded time are not objective productivity.

Pause/Resume recording, End work and Quit have distinct controls. Closing a window
keeps the menu-bar app running. Optional login launch never bypasses consent/pause.
Input Monitoring is a separate OS permission. No typed text, letter identities, app
names, window titles, URLs, screenshots or exact cursor paths are saved. Browse,
correct bounded context intervals, export or delete local recordings. Ordinary use
is survey-free; optional study checks require separate opt-in and reviewed configuration.

Guests need no account. Optional private groups keep their existing thresholds and
freeze rules, but new declared-work sync is held until a correction-compatible server
is qualified; do not advertise new group Work scoring as release-ready. Research
collection and new-format archives remain disabled. No cluster is a validated fatigue
measure and no health/productivity or intervention benefit is claimed.

## Privacy answers by shipped configuration

The checked-in configuration connects accounts but disables research. Declare
account-linked email, user ID, optional profile name/photo, and optional social
work/break duration summaries, group membership, scores and streak freeze data for
app functionality. Social summaries and group names are declared as Other Usage Data and Other
User Content for App Functionality in the privacy manifest. Email and photos are never shared with
group members. Research remains separately gated.
Do not submit the old blanket “Data Not Collected” answer for this build.

A research-enabled release additionally declares account-linked activity/usage
metrics, user-entered labels and fatigue/productivity responses. The prepared
manifest categories are Other Usage Data, Other User Content and Health, with
Analytics and Other Purposes for research/model training. Review the final taxonomy
against the actual approved protocol and Apple's questionnaire; the manifest does
not fill App Store Connect answers automatically. No advertising tracking is used.
Do not claim ongoing account-linked research qualifies for optional disclosure.

**Required final URLs:** publicly accessible privacy policy, support and approved
study information. The local website privacy draft is not a published URL. Configure
`FocusFixPrivacyPolicyURL` in Info.plist after publication. Set review contact email,
age-rating answers, territories, availability and pricing in App Store Connect.
The research restriction to adults does not by itself determine the store age rating.

## Reviewer instructions

Guest use requires no account. Choose Enable recording or Not now. Start work begins
manual capture only after recording consent and Input Monitoring are available.
Automatic recording needs its own scope acknowledgement in Privacy & Research; old
consent/OS permission/account choices cannot enable it. Setup requests occur only on
explicit action. Ordinary starts/breaks ask no survey; no reviewed study configuration
is bundled. Notification denial leaves useful in-app controls.

Inspect Unknown/Working/Not working, paused/idle/permission states in both main/menu.
End work keeps automatic activity running as Unknown, while manual-only capture
saves/stops. Pause persists across relaunch; permission restoration cannot override it.
Quit stops capture; closing a window leaves the menu-bar app running. Login launch
is separate. A notification Not working action labels from now without rewriting
preceding time; bounded history corrections retain provenance. New work sync and
research delivery remain gated as described in the readiness report.

The app uses a sandboxed, passive listen-only CGEventTap and NSWorkspace app-switch
notifications. It does not modify/post input or request Accessibility access. Secure
Input may suppress observations and is not bypassed. Guest recordings remain local;
account profile saves and research uploads have distinct controls.

For a research-enabled submission, provide a disposable reviewer account, approved
consent materials and a reviewed procedure for the upload flow in the production
service. Give Apple full access to the disclosed feature; never hide uploads during
review or enable an undisclosed collection feature afterward. Use generated sample
sessions for pre-submission infrastructure tests and keep them separate from real
participant datasets. Do not expose participant archives, management credentials,
or an administrator dashboard to reviewers. Reviewer credentials belong in App Store
Connect's private review fields, not this repository.

## Screenshots and release evidence

Capture the final signed build: main session screen, per-session planning/breaks,
Sessions, simplified Profile, and Settings → Privacy & Research. Show truthful
states with synthetic data; do not put participant IDs or real account details in
screenshots. Local verification screenshots, if present under `verification/`, are
engineering evidence, not automatically a compliant App Store screenshot set.

Run `bash scripts/test.sh`, `npm test` and `npm run test:database` in supabase,
the universal Release build, `scripts/check-release-content.py`, then signed export
verification in `scripts/verify-release.sh`. Complete fresh-Mac Input Monitoring,
notifications, sleep/wake, export/deletion, and the declared OS/hardware tests.
Complete two-account real-service upload, access-isolation and deletion tests using
generated sessions on a disposable environment; local fakes do not establish this.

## Outstanding owner/institution requirements

- Institution determination and actual study eligibility, contact, retention and
  consent terms, including future model training and any health-research requirements.
- Public privacy/study pages and a working private participant contact channel.
- Apple Developer team, registered ID, distribution identity/provisioning, private
  review contact, final screenshots and TestFlight/App Review.
- Confirm rights to distribute all code, contributions and artwork under appropriate
  App Store terms. The repository's GPL-3.0-only license remains unchanged. Ownership
  cannot be established or a separate distribution license granted by code generation.

Signing/provisioning was not configured or qualified during this redesign. Local
builds are unsigned and are not Store-distributable apps. See RELEASE.md for the existing
archive, provisioning and fresh-Mac workflow.


## Redesign release gates

See [REDESIGN-READINESS.md](REDESIGN-READINESS.md) and the unperformed signed-device
checklist. Local synthetic checks/unsigned builds are not live Input Monitoring,
login/notification qualification, study approval or submission readiness. The current
manifest's account/social off-device categories remain; new automatic activity and
study checks stay local/disabled, so no additional off-device category is activated.
Re-review against actual approved flows before any research-enabled submission.
Nothing in this draft confirms rights/signing identities or authorizes submission.
