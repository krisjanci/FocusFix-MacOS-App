# FocusFix for macOS

I am building a local activity recorder with optional work labels, rule-based break
reminders and private groups. Recorded computer use, declared work and objective
productivity are different things. This app is not a validated fatigue/health or
productivity detector. No model, real randomization or new-format research delivery
is active. See [readiness](REDESIGN-READINESS.md) for verification and release gaps.

## Recording and work labels

1. Choose **Enable recording** or **Not now**. Recording acknowledgement is separate
   from macOS Input Monitoring, automatic mode, login launch, group sync and research.
2. **Start work** starts manual work capture after consent/permission checks. The
   planning sheet can optionally set a target and tags; ordinary use asks no survey.
   Use **Enable Input Monitoring** explicitly to request setup. Opening Settings or
   accepting automatic scope does not grant/request OS access. Relaunch if macOS asks.
3. Optionally enable **automatic recording** in Settings → Privacy & Research and
   accept its separate scope. Existing installations remain manual until they opt in.
   With existing OS access, automatic capture starts while FocusFix runs, including
   non-work computer use. It begins **Unknown**. Start work is optional and labels
   from now in the existing recording, without a second input tap or writer.
4. **End work** returns automatic activity to Unknown; manual-only capture saves and
   stops. Work/Not working/Unknown are explicit context choices. They do not establish
   productivity or fatigue. **Pause recording** stops capture and persists until Resume.
   Resume after lifecycle/user pause does not inherit an old automatic work label.
5. Five continuous idle minutes, sleep/lock/display loss or permission loss stop
   capture. Eligible lifecycle resumes start Unknown; permission restoration cannot
   override user pause. Errors require deliberate retry. Missing coverage is not zero
   activity. **Quit** stops capture; closing a window leaves the menu-bar app running.
6. Optional **Launch at login** uses the public main-app service API and shows actual
   approval/status. It changes only on explicit action and cannot bypass consent/pause.

The main window and menu share recording state. The timer is recorded elapsed time;
declared-work time is separate. Local day/timezone rotation retains logical recording
and context IDs without resetting the break cooldown. Elapsed durations use a
continuous monotonic clock. A sampling gap over five seconds is not backfilled.
Crash recovery finalizes only durably checkpointed data, never downtime.

## Breaks and notifications

The shipped fixed baseline waits 25 minutes and two distinct five-second idle gaps
in the preceding minute. Skip waits 25 minutes; snooze waits 10. Reminders default
to declared work. A separate off-by-default preference permits **screen-use break
reminders** during Unknown/Not working activity without calling that work.

**I’m not working** on a notification labels from its action time forward and keeps
recording. Use history for earlier corrections. Stable recording/work-period/context
and policy IDs reject stale/duplicate actions. Requests are not proof of delivery or
viewing; no response is missing response data, not work/fatigue/rest confirmation.
Notifications are optional; equivalent controls remain in the app/menu when denied.

Explicit breaks have their own intervention phase, separate from context and idle.
Detailed capture pauses during planned breaks, then resumes awaiting return until
explicit return or the existing outside-app-input heuristic. This is not proof of
rest. Break duration/activity and healthy-habit credit keep their existing rules.

## History, goals, private groups and exports

History lists recording **segments/files**, distinct from user-declared work periods.
It shows declared work, non-work, unknown, explicit break, check-in/awaiting-return
and unavailable durations using observed coverage. Stationary observed mouse bins
count as coverage; absent bins do not. Secure Input can still suppress keyboard
observations, so mouse coverage does not establish complete keyboard capture.

Automatic intervals are retained even when short. Manual-only recordings keep the
existing 15-minute history threshold; earned observed work remains local progress.
Schemas 1–10 load unchanged as legacy/unknown context, not work inferred from the
old phase or whole-session tags. Unsupported/corrupt metadata stays on disk with a
visible history notice; compatible history remains usable and Export All fails
closed rather than claiming an incomplete export is complete.

**Edit context…** corrects a bounded interval in segment-relative seconds. Atomic
snapshots retain original labels, provenance and ordered revisions; stale/invalid
edits do not replace them. Raw CSV files stay intact. Tags/colors still describe
whole sessions, not individual work intervals. Existing planning, profiles, themes,
People panel and account/private-group controls remain.

Goals use durably observed declared work in normal phase, excluding other contexts,
breaks, check-ins, return waiting and unavailable time. Corrections replace new local
contributions idempotently; historical earned credit is a protected baseline. Daily
thresholds stay 60 work minutes and one explicitly completed one-minute break.
Three monthly weekday streak freezes retain their existing limits.

The old group RPC cannot reconcile decreased work totals. New-format work summaries
therefore stay in an account/service-scoped local replacement queue; group Work
scores do not yet reflect them. Existing groups, historical scores and explicit
healthy-break sync are preserved. A verified correction-compatible server capability
is required before releasing held work. See [sync dependency](supabase/DECLARED-WORK-SYNC.md).

Use **Export…** or **Export All…** for byte-preserving copies outside storage;
repeated exports do not overwrite earlier copies. Local deletion moves a recording
to Trash; exports/backups and research-cloud deletion are separate. Private sandbox
storage is normally `~/Library/Containers/io.github.krisjanci.FocusFix/Data/Library/Application Support/FocusFix/Sessions`;
Debug uses a separate `.debug` identity/container. No automatic legacy migration.

## Privacy and optional study checks

The passive Input Monitoring tap records generic keyboard/delete/repeat/hold timing,
clicks, scrolls, app-switch counts and one-second mouse distance/count summaries.
It never saves typed text, individual letter identities, app names, window titles,
URLs, screenshots or exact cursor paths. Temporary key/process/position values are
used in memory only. Custom tags/break labels intentionally save text entered by
the user; avoid sensitive details. Timing data can still be sensitive.

Ordinary manual/automatic use is survey-free. **Optional study check-ins** is a new,
off-by-default choice; old preferences or research sharing cannot activate it. A
complete separately reviewed configuration must also exist. None is bundled.
Synthetic schedules are test injections only. A frozen reviewed version would
control spacing, quiet hours, prompt cap, context at request and preceding recall
window. Turning checks off cancels pending prompts. Old responses/exports stay
readable; missing/skipped values are never zero or estimated ratings.

Accounts, group sync and research are independent choices. Accounts send the chosen
profile/authentication information to the configured service. Research collection
remains disabled in checked-in configuration. New schema 11 is rejected by live
queueing and the legacy ZIP path. The prepared archive-v2 contract requires new
reviewed automatic/non-work scope, matching account/consent, no pre-consent history,
server cap compatibility and disposable-service qualification. Limits remain 180
minutes/study day, 100 MiB raw and 25 MiB ZIP; long local segments may be ineligible.
The only new ZIP builder is test-flag-only and requires marked generated fixtures.

Private `research_eligibility.json` snapshots contain pseudonymous consent/account
references, no credentials, and are excluded from research ZIPs. Explicit whole-
folder exports may include them. Withdrawal, hosted deletion, downloaded-copy/model
inventory cleanup and local deletion retain distinct meanings. Source deletion does
not establish model unlearning. See [research operations](supabase/RESEARCH-OPERATIONS.md).

## File and analysis contracts

[RECORDING-CONTRACT.md](RECORDING-CONTRACT.md) defines schema 11, stable IDs,
capabilities, elapsed origins, half-open labels, atomic revisions, recovery,
coverage and archive boundaries. [CODE_MAP.md](CODE_MAP.md) maps implementation files.

- `events.csv`: nine existing generic event/timing/phase columns. The legacy
  `activity_phase=work` means normal intervention phase, **not a work-context label**.
- `mouse_movement.csv`: seven existing interval/distance/count/phase columns,
  `[start,end)` bins including observed stationary bins. No exact positions stored.
- `breaks.csv`: existing append-only decision/lifecycle rows; one break ID can have
  many snapshots. Use the completed end once, not a sum of lifecycle durations.
- `surveys.csv` and `survey_prompts.csv`: original response/prompt meanings and blank
  skipped/cancelled ratings remain. Workload-v1 answers are not renamed productivity.
- `session.json`: version/capabilities, IDs, UTC anchors, duration, tags/colors and
  frozen options. Segment duration subtracts `elapsed_origin_seconds` from logical
  elapsed time; UTC clock changes do not determine duration.
- `context_intervals.json`: independent context, source/effective/recorded times,
  logical IDs and revision history. Numeric Unix UTC dates are current; earlier
  local ISO dates/origin-zero snapshots remain readable without rewriting them.
- `reminders.jsonl`, `study_check_ins.jsonl`: request/action provenance and independent
  context/recall metadata. Requests are not assumed delivered or viewed.

The old Python supervised fatigue/productivity pipeline remains separate and accepts
its original work-only schemas 5–8. The new backend clustering pipeline uses schema
11, full-coverage five-minute input-rate windows and development-only fitting. Labels
and ratings are evaluation metadata, not clustering inputs. Descriptive clusters do
not measure fatigue. Independent validation reports sample/missingness/uncertainty;
small generated demos report insufficient evidence. Intervention benefit is untested.
The app selects its fixed timer provider; an alternate synthetic preview is disabled
and safely falls back for unsupported versions, missing coverage or stale models.

## Quick tour and verification

Quick tour uses an isolated in-memory practice model: automatic Unknown capture,
optional work, forward notification labels, pause/resume, breaks, history and groups.
Its actions never call the tracker, change consent/OS settings or upload. Reduce
Motion and named icon controls are preserved. **Test tracking** is different: during
real recording it observes real events in that recording; it does not open a second tap.

```sh
bash scripts/test.sh
cd supabase && npm test && npm run test:database
```

Open `FocusFix/FocusFix.xcodeproj` to build. Debug/Release target macOS 14+; source
builds do not qualify that OS/hardware range. See [REDESIGN-READINESS.md](REDESIGN-READINESS.md),
[MANUAL-QUALIFICATION.md](MANUAL-QUALIFICATION.md), [RELEASE.md](RELEASE.md) and
[STORE-SUBMISSION.md](STORE-SUBMISSION.md). No deployment, website publication, Apple
submission or push is part of this work.

## License

Copyright (c) 2026 Kristian Janci.

FocusFix's original software and project material in this repository are
licensed under the GNU General Public License, version 3 only
(`GPL-3.0-only`). You may redistribute and modify this material under those
terms. The complete license is in [LICENSE](LICENSE).

This material is distributed without any warranty, including the implied
warranties of merchantability or fitness for a particular purpose. See the
license for details. Third-party components retain their own licenses and
notices; this grant applies only to material whose rights are held by
Kristian Janci.
