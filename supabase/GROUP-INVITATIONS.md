# Group invitations and administration

The desktop update requires `202611120001_group_invitations_and_admin.sql`, after the existing current-work-streak migration. Apply the SQL once in a transaction. It preserves the existing group IDs, members, invite codes, event history and lifetime counters for older clients.

The admin can invite an existing FocusFix account by email, rename the group, edit its description, remove members, and transfer the admin role to a current member. Transferring changes the existing owner field; the former admin immediately loses management access. Only the current admin receives the invite code.

Invitations appear in the recipient's private inbox and expire after 30 days. Repeated invitations to the same account and group update one inbox item. The Groups button shows a notification dot, and the app refreshes every 30 seconds while running. Refresh is also available manually. Recipients can decline without enabling progress sharing. Accepting explicitly enables summary sync, creates membership subject to the existing 50-member/20-group limits, and starts group scoring at the time of joining. No historical recording is uploaded by accepting an invitation.

The server exposes only group ID, invitation ID, group name and admin display name in each inbox item. Direct invitation-table access is denied, and anonymous callers cannot access inbox or response functions. Invitation submission deliberately gives the same result for unavailable accounts; it does not expose an email directory.

Healthy habits now rank current weekday streaks instead of lifetime qualifying-day totals. A completed break of at least one minute qualifies a day. The same weekend, three-monthly-freeze and missed-day reset rules used by work streaks apply independently to healthy habits. The main app's flame remains the declared-work streak. Old servers do not supply healthy-habit streak fields; updated clients show unavailable scores rather than representing lifetime points as streaks.

Run `npm run test:database` for isolated PostgreSQL tests. They cover inbox isolation, duplicate invites, accept/decline, role transfer and removal, input validation, private helper grants, and healthy-habit resets, alongside the existing group-capacity and work-streak regressions. Run `bash scripts/test.sh` from the repository root for desktop behavior tests.

Deployment must be verified separately from local checks. Until the migration is applied and a new app build is distributed, people using the previous download do not have these features.
