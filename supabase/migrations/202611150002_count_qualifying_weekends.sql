-- Completed weekend goals add streak days. Uncompleted weekends remain optional.
-- Existing history is recalculated at read time; no progress rows are changed.
create or replace function public.social_group_work_streak(member_id uuid, selected_group uuid, as_of timestamptz)
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
  select coalesce(sum(s.seconds),0) into seconds_worked from public.social_member_days s
   where s.group_id=selected_group and s.user_id=member_id and s.day=d;
  if seconds_worked>=3600 then streak:=streak+1; frozen:=false;
  elsif extract(isodow from d)<=5 and d<today then
    if streak>0 and (last_frozen is null or last_frozen<>d-1) and used<3 then
     used:=used+1; last_frozen:=d; frozen:=true;
    else streak:=0; frozen:=false;
    end if;
  end if;
  d:=d+1;
 end loop;
 return next;
end;
$$;
revoke all on function public.social_group_work_streak(uuid,uuid,timestamptz) from public,anon,authenticated;

create or replace function public.social_group_habit_streak(member_id uuid, selected_group uuid, as_of timestamptz)
returns table(streak integer, frozen boolean)
language plpgsql volatile set search_path='' as $$
declare
 zone text; joined timestamptz; today date; d date; month_key text := '';
 used integer := 0; last_frozen date; healthy_day boolean;
begin
 select a.timezone,m.joined_at into zone,joined from public.social_members m
 join public.social_accounts a on a.user_id=m.user_id where m.group_id=selected_group and m.user_id=member_id;
 streak:=0; frozen:=false;
 if joined is null then return next; return; end if;
 today:=(as_of at time zone zone)::date; d:=(joined at time zone zone)::date;
 while d<=today loop
  if month_key<>to_char(d,'YYYY-MM') then used:=0; month_key:=to_char(d,'YYYY-MM'); end if;
  select coalesce(bool_or(s.healthy),false) into healthy_day from public.social_member_days s
   where s.group_id=selected_group and s.user_id=member_id and s.day=d;
  if healthy_day then streak:=streak+1; frozen:=false;
  elsif extract(isodow from d)<=5 and d<today then
    if streak>0 and (last_frozen is null or last_frozen<>d-1) and used<3 then
     used:=used+1; last_frozen:=d; frozen:=true;
    else streak:=0; frozen:=false;
    end if;
  end if;
  d:=d+1;
 end loop;
 return next;
end;
$$;
revoke all on function public.social_group_habit_streak(uuid,uuid,timestamptz) from public,anon,authenticated;

-- Keep the legacy account-wide freeze reconciliation consistent with weekend starts.
-- Patch only the known weekday gate; preserve authentication, ingestion and grants.
do $migration$
declare
 definition text := pg_get_functiondef('public.social_state_daily_points(text,jsonb)'::regprocedure);
 old_gate text := $old$if extract(isodow from d)<=5 then
   if coalesce((select seconds from public.social_days where user_id=caller and day=d),0)>=3600 then alive:=true;$old$;
 new_gate text := $new$if extract(isodow from d)<=5 or coalesce((select seconds from public.social_days where user_id=caller and day=d),0)>=3600 then
   if coalesce((select seconds from public.social_days where user_id=caller and day=d),0)>=3600 then alive:=true;$new$;
begin
 if position(old_gate in definition)=0 then raise exception 'Unexpected account freeze function; review weekend migration'; end if;
 execute replace(definition,old_gate,new_gate);
end;
$migration$;
