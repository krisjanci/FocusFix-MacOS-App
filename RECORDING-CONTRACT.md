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
effective/action-recorded times and `[start,end)` elapsed seconds. Only the final
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
