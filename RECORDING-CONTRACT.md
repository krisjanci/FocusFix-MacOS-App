# Local recording contract — schema 11

I separate recording mode (manual/automatic), capture state (disabled, ready,
recording, user-paused, idle-paused, permission-unavailable), activity context
(work, non_work, unknown) and intervention phase (normal, explicit_break,
check_in, awaiting_return). Reasons describe unavailable/paused state. Work is a
user declaration, not verified productivity. Unknown is not non-work; a break is
an intervention, not a context label.

`session.json` declares `schema_version=11`, `recording_format=focusfix.recording.v11`,
required capabilities, recording/segment UUIDs, recording mode and the context file.
A compatible reader must check all capabilities and reject unsupported versions.
The separate atomic `context_intervals.json` is the authoritative label snapshot.
Each interval has a unique ID, a logical continuity ID, context, source, UTC
effective/action-recorded times (numeric Unix UTC seconds, preserving subsecond action timing) and `[start,end)` elapsed seconds. Only the final
interval of an unfinished recording can have a null end. Bounds must be finite,
nonnegative, within observed coverage and nonoverlapping. Empty completed recordings
have no intervals. `observedThrough` bounds the snapshot; final metadata duration
must match it. Elapsed times use the existing continuous monotonic clock, never
wall-clock differences. UTC timestamps order actions; timezone/clock changes do
not determine duration. Recorded end UTC remains start plus elapsed in the legacy
metadata, a derived ordering anchor rather than a sampled wall-clock end.

Manual Start declares work. Automatic recordings will begin unknown. The CSV
`activity_phase=work` still means the old normal intervention phase. It must never
be used as a work-context label. Schemas 1–10 stay unchanged and load as legacy/
unknown context; whole-session tags are not interval-level explicit declarations.
The event and mouse CSV columns and export copying remain unchanged. Label saves
replace the context snapshot atomically, without rewriting activity files.

The context snapshot reserves ordered revisions for bounded history corrections.
Automatic capture, consent, lifecycle, editing and UI integration follow in later
steps. This contract alone does not enable automatic recording.

## Research boundary

New-schema recordings are local only. Both completed-session queueing and archive
construction reject schema 11; old archives remain supported. Step 9 must explicitly
review the allowlist for `context_intervals.json`, all required capabilities,
provenance/revisions and any future coverage/check-in files. Old consent must not
cover new automatic/non-work data. Increasing ZIP limits cannot bypass daily study
caps. These changes do not enable research or establish study approval.

## Step 3: file segments and durable coverage

Rotation keeps one logical recording clock. A segment's `elapsed_origin_seconds`
(and context `elapsedOrigin`) is its start on that clock. CSV elapsed values and
label bounds stay on the logical clock; segment duration is observedThrough minus
origin. Recording ID and an active label's logical ID survive rotation; segment
IDs change. Break-policy timing and cooldown do not reset. UTC segment start is
sampled separately; timezone changes may trigger a new segment without changing
elapsed bounds. This avoids negative/overlapping elapsed intervals after clock edits.

Each sampling tick synchronizes event/mouse bytes before atomically checkpointing
`observedThrough`. After interruption, recovery finalizes only that checkpoint,
keeps raw bytes intact and marks any uncheckpointed tail ineligible. There is no
attempt to infer activity between the checkpoint and restart. A run-loop sampling
gap over five seconds closes capture at its last observation rather than generating
stationary bins across the gap. Automatic recordings, including short ones, are
retained. Unknown computer use is not credited to work goals.

One controller evaluates recording consent, automatic scope, durable user pause,
permission availability, sleep/display/login blockers, idle, failure and quit.
Idle cutoff defaults to 300 continuous seconds; idle resume reads the public OS
idle counter and does not install a second logger. Lifecycle resume creates a new
unknown recording. Failures require deliberate Resume/Start to retry. Actual
sleep/wake/lock, permission delivery and long-run resource use remain manual checks.

## Step 4: context actions and corrections

Start work on an existing automatic recording changes context from that action
forward, with one tap/writer. End work returns automatic activity to unknown;
manual-only End work saves/stops capture. Work, Not working and Unknown are
available in the menu. Repeated Start work preserves the existing logical work ID.
Labels survive rotation and ordinary app switching; idle, lifecycle/user pause and
End work clear active intent. Break phase remains independent of work intention.

The history editor accepts a bounded interval in segment-relative seconds, then
converts it to the logical elapsed origin. It checks the latest revision before
saving. The atomic snapshot contains ordered revisions with original intervals,
source/effective/action-recorded times (numeric Unix UTC seconds, preserving subsecond action timing) and idempotent correction IDs. Invalid or
stale edits leave the snapshot and raw files untouched. The snapshot is capped at
16 MiB; a size failure retains the previous readable labels. Legacy labels/files
are unchanged and cannot be assigned invented historical context by this path.

## Step 5: honest reminder requests

`reminders.jsonl` is append-only scheduled/requested/action history, including the
logical recording, context/work-period IDs, policy version, context, elapsed
schedule/action and UTC request/action-recorded times. Requested does not mean
delivered/viewed. An unanswered notification adds no rating, context confirmation
or break-completion evidence. This file must be reviewed in Step 9's allowlist.

The shipped policy remains the 25-minute/two-idle-gap baseline, eligible only for
declared work by default. A separate screen-use reminder preference includes
unknown/non-work without treating it as work. Notification Not working changes
context forward from the action and leaves capture running; history edits are
separate. Context/pause/revoke changes invalidate pending requests. Consumed
requests cannot be applied twice. Logical IDs and a process-monotonic cooldown
survive file rotation, avoiding stacked requests.

## Step 6: coverage in history

Recording files/segments are distinct from logical user work periods. History
calculates declared work, non-work and unknown only where mouse-summary coverage
was observed in normal intervention phase. Zero-movement observed bins count as
coverage; absent bins do not. Explicit break intervals come from break lifecycle
records, including continued breaks across segments. Check-in/awaiting-return
coverage is shown separately, and remaining duration is unavailable. No keyboard
capture completeness is implied by mouse coverage; Secure Input limitations remain.
Overlapping/malformed coverage fails closed instead of inflating durations.

Selected history coverage is computed off the main actor with a per-file read
limit. Legacy recordings retain unknown context. Local deletion, exports and
research deletion keep their separate meanings. The main status and menu use one
pure presentation function. The tour's automatic/label/pause controls modify only
its in-memory practice model, never the real tracker, consent, permissions or cloud.

## Step 7: optional study measurement, ordinary use survey-free

The original survey switches and answers remain intact, but an independent new
study-check-in opt-in (version, accepted scope and action UTC) is required. Old
preferences/research sharing do not activate it. With no complete reviewed bundled
configuration, live snapshots disable every survey. The repository supplies no
reviewed configuration. A synthetic configuration is accepted only through an
explicit isolated test injection. Real approval/consent terms are not fabricated.

A configuration names its review reference, consent scope, frozen schedule version,
spacing, recall window, rolling-24-hour cap and quiet local hours. The stored rate
budget survives relaunch; malformed state fails closed. Ordinary automatic/manual
starts and break flows require no ratings. Explicit study revocation immediately
cancels pending opportunities. Enabling/options changes wait for a new recording.

`study_check_ins.jsonl` joins immutable check-in IDs to activity context at request,
schedule/scope, recording ID and preceding recall bounds. End of recall is request
time, before opening/answering; check-in interaction is never preceding predictor
data. The existing survey/prompt CSVs retain their original meanings and blank
skip/cancel values. Separate logs distinguish requested/opened/answered/skipped/
cancelled/withdrawn; requests are not proof of delivery. The new file will require
Step 9 allowlist/scope review. The old work-only supervised backend rejects schema
11 and cannot consume cross-context study checks without a new adapter/evaluation.
