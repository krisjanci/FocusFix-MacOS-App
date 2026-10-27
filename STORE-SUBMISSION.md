# FocusFix Mac App Store submission package

Prepared October 26, 2026. Draft materials and verification instructions, not a
submitted/approved app. No Apple agreement, license exception or rights assignment
is accepted or created by this implementation.

## Listing copy

**Name:** FocusFix (availability to be checked in App Store Connect)

**Subtitle:** Activity patterns and breaks

**Category:** Productivity. **Minimum target:** macOS 14; verify actual supported
OS/hardware combinations before advertising them. **Bundle ID:** io.github.krisjanci.FocusFix.

**Description:**

FocusFix helps you notice activity patterns and make time for breaks on your Mac.
Start a session to record keyboard timing, clicks, scrolling and summarized mouse
movement. Plan breaks, receive reminders, and optionally reflect on fatigue and
productivity through short check-ins.

Choose whether to enable activity recording, then start each session yourself.
Browse saved sessions, export recordings or delete local copies. Input Monitoring
permission allows activity measurement across apps. FocusFix does not save typed
text, individual letter keys, app names, screenshots or exact cursor paths.

Use FocusFix locally as a guest, or create a private account for your profile.
Optionally enable progress sync and join private groups with invite codes. Work
and Healthy habits leaderboards award daily points for 60 minutes of work and a
completed one-minute break. Three automatic monthly freezes protect your weekday
work streak without adding points. Group members see only names, standard avatars
and scores.
If an approved study is open, eligible adults can request to participate. Research
participation requires manual approval and separate consent before new completed
sessions upload to private storage. Declining research does not remove local features.
Manage recording and sharing in Settings → Privacy & Research.

FocusFix is experimental. Break reminders use timing and idle rules; the app is not
a medical device or a validated fatigue or productivity detector.

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

Guest use requires no account. On first entry, choose Enable recording or Not now.
Consent does not start recording or grant OS permission. Use Start session, then
separately enable Input Monitoring in System Settings when prompted. Relaunch if
macOS requests it and start a session again. Surveys and notifications are optional.
The menu bar and main window show recording state. Stop & save, disabling recording,
permission interruption or Quit ends capture. Closing the main window leaves the
menu-bar app running.

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

No signing identity was available on this Mac during implementation. An unsigned
or ad hoc build is not a Store-distributable app. See RELEASE.md for the existing
archive, provisioning and fresh-Mac workflow.
