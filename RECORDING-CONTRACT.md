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
