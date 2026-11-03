# Declared-work replacement sync: release dependency

I inspected the checked-in `social_state` RPC: it accepts positive increments,
deduplicates immutable event IDs and adds work seconds to daily/member rows. It
cannot reduce a previously accepted duration. Sending a new event for a correction
would inflate totals; reusing the old ID would silently discard the correction.
No migration or function was deployed during this redesign.

Local progress version 2 preserves legacy work as its baseline and stores each new
segment's day allocations, revision and captured account scope. Corrections replace
only that contribution. The social ledger has a distinct version-2 replacement
outbox, scoped to owner and service origin. It is never serialized into the legacy
RPC's `events` array. Old private groups, healthy-break events, point thresholds and
freeze rules retain their existing behavior. New work remains local pending a
compatible service. Signing out/account changes cannot transfer pending records.

Before enabling new work sync, implement/review an additive authenticated RPC that:

- accepts owner-scoped segment IDs, increasing revision numbers, fixed scoring
  timezone and replacement observed-work intervals, with retry-safe acknowledgements;
- retains a separate immutable legacy baseline and recomputes affected daily/member
  contributions transactionally for increases and decreases, respecting account
  activation and each group's join boundary;
- rejects stale/conflicting revisions, unsupported contracts, invalid bounds,
  cross-account segments, pre-activation/backfilled work and nonfinite durations;
- preserves explicit-break scoring and three monthly nonconsecutive weekday freezes;
- exposes a verified capability version, tested in isolated PostgreSQL and a disposable
  service, before the client can release held replacement records.

Do not infer capability from a successful legacy sync, deploy this draft to the
participant project, or send held new data to test the old RPC. Current group Work
scores therefore differ from new local declared-work totals. These are declared
minutes, not quality-adjusted output or objective productivity.
