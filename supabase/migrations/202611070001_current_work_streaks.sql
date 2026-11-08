-- Keep the existing summary ingestion and lifetime points for older clients.
-- Compute current weekday streaks on every read, including members who have not
-- opened FocusFix since missing a day. No recorded work or earned points is deleted.
alter function public.social_state(text,jsonb) rename to social_state_daily_points;
revoke all on function public.social_state_daily_points(text,jsonb) from public,anon,authenticated;

create function public.social_group_work_streak(member_id uuid, selected_group uuid, as_of timestamptz)
returns table(streak integer, frozen boolean)
language plpgsql volatile set search_path = '' as $$
declare
 zone text; joined timestamptz; today date; d date; month_key text := '';
 used integer := 0; last_frozen date; seconds_worked double precision;
begin
 select a.timezone,m.joined_at into zone,joined
 from public.social_members m join public.social_accounts a on a.user_id=m.user_id
 where m.group_id=selected_group and m.user_id=member_id;
 streak := 0; frozen := false;
 if joined is null then return next; return; end if;
 today := (as_of at time zone zone)::date;
 d := (joined at time zone zone)::date;
 while d<=today loop
  if month_key<>to_char(d,'YYYY-MM') then used:=0; month_key:=to_char(d,'YYYY-MM'); end if;
  if extract(isodow from d)<=5 then
   select coalesce(sum(s.seconds),0) into seconds_worked from public.social_member_days s
    where s.group_id=selected_group and s.user_id=member_id and s.day=d;
   if seconds_worked>=3600 then streak:=streak+1; frozen:=false;
   elsif d<today then
    if streak>0 and (last_frozen is null or last_frozen<>d-1) and used<3 then
     used:=used+1; last_frozen:=d; frozen:=true;
    else streak:=0; frozen:=false;
    end if;
   end if;
  end if;
  d:=d+1;
 end loop;
 return next;
end;
$$;
revoke all on function public.social_group_work_streak(uuid,uuid,timestamptz) from public,anon,authenticated;

create function public.social_state(p_action text default 'sync', p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare state jsonb; groups_json jsonb;
begin
 -- The original function still authenticates, locks, validates and deduplicates
 -- summaries, enforces membership, and omits private profiles and invite codes.
 state := public.social_state_daily_points(p_action,p_payload);
 if state ? 'error' then return state; end if;
 select coalesce(jsonb_agg(g || jsonb_build_object('members',(
  select coalesce(jsonb_agg(member || jsonb_build_object(
   'workStreak',streak,'workStreakFrozen',frozen,'workStreakRank',streak_rank)
   order by member->>'name',member->>'id'),'[]'::jsonb)
  from (
   select member,s.streak,s.frozen,rank() over(order by s.streak desc) streak_rank
   from jsonb_array_elements(g->'members') member
   cross join lateral public.social_group_work_streak((member->>'id')::uuid,(g->>'id')::uuid,now()) s
  ) scored
 )) order by g->>'name'),'[]'::jsonb) into groups_json
 from jsonb_array_elements(state->'groups') g;
 return state || jsonb_build_object('groups',groups_json,'workStreakVersion',1);
end;
$$;
revoke all on function public.social_state(text,jsonb) from public,anon;
grant execute on function public.social_state(text,jsonb) to authenticated;
