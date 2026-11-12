# Declared-work replacement sync

Migration `202611120003_declared_work_and_group_photos.sql` adds the authenticated
`sync_declared_work` RPC. The app negotiates `declaredWorkSyncVersion: 1` before
sending its durable replacement outbox. Older servers keep that outbox local.
The increment-only legacy RPC never receives these replacements.

Each recording keeps its captured account/service scope, immutable segment ID,
increasing revision, recording bounds and observed declared-work intervals. The
server splits intervals at midnight in the account's fixed scoring timezone and
clips them to account activation and group membership. It replaces each segment's
contribution transactionally, preserving legacy work, explicit-break credit and
freeze rules. Identical retries are acknowledged without adding credit; conflicting
revisions and cross-account overwrites fail. Older revisions cannot restore work.
The client acknowledges only the exact version sent, preserving corrections made
while a request is in flight. Offline records survive restarts and account changes.
Finalized owned recordings upgrade previously held day-only totals from their local
coverage; guest recordings never transfer to a signed-in account.

Only interval summaries cross this boundary, never raw input events, labels,
application names, URLs, surveys or recording files. These are declared minutes,
not a measure of work quality or objective productivity.

Group photo sharing is separately optional. Existing private photos remain private.
The profile editor produces a bounded 64-pixel thumbnail only when the user enables
sharing and saves. The social response returns only `groupPhoto`, never the original
private photo. Turning sharing off removes it from future responses. Each user sees
their own account photo locally even without sharing it.

Run `npm --prefix supabase run test:database` for isolated PostgreSQL checks.
`tests/declared-work-live.sql` repeats replacement, retry, correction, ownership,
membership and thumbnail privacy checks with synthetic fixtures inside a rollback.
