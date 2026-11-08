# Current Work leaderboard streaks

The old Work score was a lifetime count of qualifying work days since joining.
It could stay at 1 indefinitely after missed days. The new Work leaderboard uses
`workStreak`, `workStreakRank`, and `workStreakFrozen`; it never treats an old
`work` total as a current streak. Healthy habits retains its lifetime daily scores.

Apply `migrations/202611070001_current_work_streaks.sql` after the existing group
migration. The wrapper preserves summary validation, retry deduplication, access
control and lifetime history. Private helpers are inaccessible to client roles.
Old clients retain the old fields. An updated client connected to an old server
shows an unavailable streak (—) instead of relabeling lifetime points.

Each member's Work streak starts with qualifying weekdays after joining that
group, using their saved scoring timezone. Sixty minutes earns one weekday.
Today stays provisional; weekends neither earn nor break a streak. Three freezes
refill monthly without rollover; consecutive calendar dates cannot both be frozen.
A freeze preserves the count without adding a day. An unprotected past weekday
resets the count to zero. Read-time calculation includes inactive members and
late-arriving summaries, so no member login or scheduled reset job is required.

The main-window flame shows personal local progress; a group's streak covers
eligible work since joining that group. The existing restriction on new-schema
work uploads remains in force; see `DECLARED-WORK-SYNC.md`. This migration does
not enable replacement uploads or send held recordings to the old increment RPC.

Verify locally with `npm --prefix supabase run test:database` and
`bash scripts/test.sh`. The database runner exercises the new migration with
synthetic users, missed days, freezes, thawing, weekends, month boundaries,
inactive-member ranking, helper permissions and the existing group/RLS tests.

The update was verified on the configured FocusFix project on November 7, 2026.
The preflight matched the original function body exactly. Post-deployment hashes
matched the new wrapper and helper, and confirmed the preserved original body.
Authenticated clients can execute only the public wrapper; both helpers remain
private. The full `work-streaks.sql` transaction passed against the live service,
including its assertion-dependent success marker, and rolled back its fixtures.
The running app received a zero-day current group streak with the grey flame;
two zero-day members shared rank 1. Healthy habits retained its all-time score.
See `verification/streak-fixes.json` and `verification/streak-live-regressions.png`.

If this migration needs to be reversed, the preserved original function can be
restored without changing recorded history:

```sql
begin;
drop function public.social_state(text,jsonb);
drop function public.social_group_work_streak(uuid,uuid,timestamptz);
alter function public.social_state_daily_points(text,jsonb) rename to social_state;
grant execute on function public.social_state(text,jsonb) to authenticated;
commit;
```
