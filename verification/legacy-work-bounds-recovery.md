# Historical work-sync recovery

Verified November 15, 2026 against the running Xcode Debug app and its configured service.

The earlier app-side repair rebuilt precise recording summaries, but six historical segments had already been accepted by the server with whole-second starts. Their precise replacement revisions consequently failed the immutable-start check. A read-only comparison confirmed all six stored starts were rounded, while the local capture manifests retained fractional seconds.

Migration `202611150001_repair_rounded_work_bounds.sql` permits only a newer revision that translates a whole-second start forward by less than one second, translating the observation end and every work interval by the same amount within two microseconds of storage precision. Interval counts and work durations cannot change during this repair. Once precise, the start remains immutable. Ownership, replay, overlap, timezone, membership clipping and backwards-end checks remain enforced.

All isolated database checks passed, including regression cases for historical precision repair, repeated retries, persisted precision, unchanged duration credit, rejected interval expansion, nonuniform shifts, changes to already precise starts, and backwards observation ends.

The live function was checked against the original implementation before updating it. Its normalized body hash after installation matched the tested migration (`315cea64d6afd3bf6f34a1a9fd680a31`). Retrying from the actual Xcode app then cleared all six ready historical summaries from its durable outbox and removed the Retry needed warning. Original recording files were not rewritten or deleted.

Seven older day-only entries remain local and unsent; no matching saved capture manifests were found for those IDs. They cannot be safely reconstructed from day totals and do not cause the rejected-bound errors. The app may still display pending progress for these held entries. No app release, version bump, archive or distribution was created.
