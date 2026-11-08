-- Synthetic regression fixtures; no user data survives this transaction.
begin;
do $$
declare
 a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); g uuid := gen_random_uuid();
 result record; state jsonb; member jsonb; today date := (now() at time zone 'UTC')::date; last_work date;
begin
 insert into auth.users(id,email) values(a,'streak-a@example.invalid'),(b,'streak-b@example.invalid');
 insert into public.social_accounts(user_id,timezone,activated_at) values(a,'UTC','2026-01-01'),(b,'UTC','2026-01-01');
 insert into public.social_groups(id,owner,name) values(g,a,'Synthetic streak regression');
 insert into public.social_members(group_id,user_id,joined_at) values(g,a,'2026-10-19'),(g,b,'2026-10-19');
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,a,'2026-10-19',3600);
 select * into result from public.social_group_work_streak(a,g,'2026-10-19T16:00:00Z');
 if result.streak<>1 or result.frozen then raise exception 'Earned streak failed'; end if;
 select * into result from public.social_group_work_streak(a,g,'2026-10-21T16:00:00Z');
 if result.streak<>1 or not result.frozen then raise exception 'Single missed weekday not frozen'; end if;
 select * into result from public.social_group_work_streak(a,g,'2026-10-22T16:00:00Z');
 if result.streak<>0 or result.frozen then raise exception 'Consecutive missed weekdays did not break streak'; end if;
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,a,'2026-10-21',3600);
 select * into result from public.social_group_work_streak(a,g,'2026-10-21T16:00:00Z');
 if result.streak<>2 or result.frozen then raise exception 'New work did not thaw streak'; end if;
 -- A weekend neither adds days nor hides the preceding protected Friday.
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,b,'2026-10-22',3600);
 select * into result from public.social_group_work_streak(b,g,'2026-10-26T16:00:00Z');
 if result.streak<>1 or not result.frozen then raise exception 'Weekend freeze failed'; end if;
 select * into result from public.social_group_work_streak(b,g,'2026-10-28T16:00:00Z');
 if result.streak<>0 or result.frozen then raise exception 'Missed Tuesday did not end frozen streak'; end if;
 -- Month refill cannot bypass the no-consecutive-date rule.
 delete from public.social_member_days where group_id=g;
 update public.social_members set joined_at='2026-09-29' where group_id=g;
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,a,'2026-09-29',3600);
 select * into result from public.social_group_work_streak(a,g,'2026-10-02T16:00:00Z');
 if result.streak<>0 then raise exception 'Month change incorrectly revived streak'; end if;
 -- The wrapper must rank an inactive member below an active member without
 -- requiring the inactive member to log in. Lifetime points remain untouched.
 delete from public.social_member_days where group_id=g;
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,a,'2026-01-01',3600);
 last_work:=today;
 while extract(isodow from last_work)>5 loop last_work:=last_work-1; end loop;
 insert into public.social_member_days(group_id,user_id,day,seconds) values(g,b,last_work,3600);
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.social_state('sync','{"timezone":"UTC"}');
 if (state->>'workStreakVersion')::int<>1 then raise exception 'Capability missing'; end if;
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=a::text;
 if (member->>'work')::int<>1 or (member->>'workStreak')::int<>0 or (member->>'workStreakRank')::int<>2 then raise exception 'Inactive member retained streak or rank'; end if;
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=b::text;
 if (member->>'workStreak')::int<>1 or (member->>'workStreakRank')::int<>1 then raise exception 'Current streak not ranked first'; end if;
 if has_function_privilege('authenticated','public.social_group_work_streak(uuid,uuid,timestamptz)','execute')
 or has_function_privilege('authenticated','public.social_state_daily_points(text,jsonb)','execute') then raise exception 'Private helper exposed'; end if;
end $$;
rollback;
