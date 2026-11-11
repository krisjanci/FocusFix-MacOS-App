# Development sharing operations

This is product-development sharing for the personal FocusFix app. It is separate from the disabled research pipeline. Detailed recordings are sensitive, account-linked data. The published app needs an accurate privacy page and App Store privacy answers before distribution.

## Deploy in order

1. Apply all existing Supabase migrations, then `202611100001_development_sharing.sql`. It creates the private `development-recordings` bucket, consent/deletion tables, access policies, and a default-off collection switch.
2. Deploy `delete-development-data`, then the updated `delete-account` Edge Function. Keep the service-role key in the Edge Function environment only. Never put it in the Mac app, website, Git repository, or a public issue.
3. In a disposable project, test account approval, user consent, one upload, collection off, withdrawal, hosted deletion, and account deletion with synthetic recordings. Check that a second account cannot read or upload the first account’s files.
4. Review the published privacy page, final App Store privacy answers, and server backup/deletion practice. Then deploy the same migration/functions to the production project. Collection stays off until you deliberately enable it.

A public client key beginning `sb_publishable_` is expected in the app. Access depends on the server policies, manual approval, and user consent; hiding the public key is not a security control.

## Approve a signed-in account

Find the person’s account ID in Supabase Auth. Use the SQL editor with administrator access. The example limit allows up to ten archives for this account; each archive has a 25 MiB object limit.

```sql
insert into public.development_approvals (user_id, enabled, max_archives)
values ('ACCOUNT_UUID', true, 10)
on conflict (user_id) do update
set enabled = excluded.enabled, max_archives = excluded.max_archives, updated_at = now();
```

The user must still sign in, refresh sharing status, read the explanation, and choose **I agree and enable sharing**. Approval alone never uploads data. Existing recordings are never backfilled.

Enable collection only while you have capacity:

```sql
update public.development_collection set enabled = true, updated_at = now()
where singleton = true;
```

Set `enabled = false` to pause everyone. For one account, set `development_approvals.enabled = false`. To raise or lower a limit, update `max_archives` (1–100). A lower limit stops new uploads but does not remove existing files. Monitor Supabase storage and keep the switch off when you cannot review incoming data.

## Withdrawal, deletion, and retention

Turning sharing off immediately cancels pending uploads on that Mac. The client records a server withdrawal when it can connect with the same account. An offline device cannot revoke the server until then. Hosted recordings remain until the user requests deletion. The **Request deletion** action records a durable request, stops future uploads, and removes that user’s hosted files. Account deletion invokes the same cleanup before deleting the account.

Treat a request marked `hosted_deleted` as unfinished if you downloaded copies. Keep a private inventory of downloaded files and backups, remove the user’s copies, and document when service backups expire or are purged. Only after the actual work is complete should an administrator mark the request `completed` and set `completed_at`. Do not claim that local exports, user backups, or derived model effects were deleted by the server action. Do not use uploaded recordings outside the stated individual product-development purpose.

Never paste raw recordings into public issues. Store admin credentials outside the repository, restrict dashboard access, and review the deletion-request table regularly.
