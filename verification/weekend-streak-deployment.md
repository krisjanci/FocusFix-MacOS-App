# Weekend group streak repair

Verified and deployed November 18, 2026 on the configured FocusFix project.

The app and repository already counted qualifying weekend days, but the live
database still ran weekday-only work and healthy-habit streak helpers. Both live
helper bodies exactly matched their pre-weekend migration versions. This explained
why the group calculation omitted completed Saturdays and Sundays.

Applied `supabase/migrations/202611150002_count_qualifying_weekends.sql` inside one
transaction. Existing qualifying history now counts on every group read; no user
progress rows were rewritten. Missed weekends remain optional and spend no freezes.
The existing group membership and scoring timezone boundaries remain in effect.

Post-deployment `md5(prosrc)` values matched the tested migration:

| Function | Body hash | Authenticated direct execution |
| --- | --- | --- |
| `social_group_work_streak` | `6f2318ff3c99b4ada7ef2cee834a7cc9` | Denied |
| `social_group_habit_streak` | `6e3f747610fdc7881a29ecf8827b338a` | Denied |
| `social_state_daily_points` | `88e78fefef7aeb7bdbdb3fa66b7feb28` | Denied |

All isolated database migrations and regressions passed with
`npm --prefix supabase run test:database`. The strengthened
`supabase/tests/work-streaks.sql` also passed against the live service, returning
`current_streak_regressions_passed = true` after all assertions, then rolling back
every synthetic fixture. Checks include independent work/habit weekend credit,
3599 versus 3600 seconds, Saturday and Sunday additions, timezone boundaries,
weekend starts, freezes, missed-weekday resets, late work, ranking and permissions.
See `weekend-streak-live-regressions.png` for the live result.
