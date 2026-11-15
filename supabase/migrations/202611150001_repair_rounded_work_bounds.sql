-- Repair legacy replay precision without accepting arbitrary recording-bound changes.
create or replace function public.sync_declared_work(p_segments jsonb,p_timezone text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 caller uuid:=auth.uid(); zone text; activation timestamptz; item jsonb; piece jsonb;
 sid uuid; rev integer; first_time double precision; last_time double precision;
 lo double precision; hi double precision; last_end double precision; old public.social_work_segments%rowtype;
 legacy_shift double precision; repairs_rounded_start boolean;
 begin_at timestamptz; end_at timestamptz; cursor_time timestamptz; boundary timestamptz; d date; m record;
 ack jsonb:='[]'::jsonb;
begin
 if caller is null then raise exception 'Sign in to sync work'; end if;
 select timezone,activated_at into zone,activation from public.social_accounts where user_id=caller for update;
 if zone is null then raise exception 'Enable group progress before syncing work'; end if;
 if p_timezone is distinct from zone then raise exception 'Scoring timezone mismatch'; end if;
 if jsonb_typeof(p_segments) is distinct from 'array' or jsonb_array_length(p_segments)>50 then
  raise exception 'Invalid work replacement batch'; end if;
 for item in select value from jsonb_array_elements(p_segments) loop
  sid:=(item->>'segmentID')::uuid; rev:=(item->>'revision')::integer;
  first_time:=(item->>'startedAt')::double precision; last_time:=(item->>'observedThrough')::double precision;
  if (item->>'ownerID')::uuid is distinct from caller or (item->>'contractVersion')::int is distinct from 2
   or sid is null or rev is null or rev<1 or first_time is null or last_time is null
   or not(first_time>=0 and first_time<'Infinity'::double precision)
   or not(last_time>=first_time and last_time<'Infinity'::double precision)
   or last_time-first_time>604800 or to_timestamp(last_time)>now()+interval '5 minutes'
   or jsonb_typeof(item->'intervals') is distinct from 'array' or jsonb_array_length(item->'intervals')>4096 then
   raise exception 'Invalid declared-work replacement'; end if;
  last_end:=first_time;
  for piece in select value from jsonb_array_elements(item->'intervals') loop
   lo:=(piece->>'start')::double precision; hi:=(piece->>'end')::double precision;
   if lo is null or hi is null or not(lo>=last_end and hi>lo and hi<=last_time) then
    raise exception 'Invalid or overlapping work intervals'; end if;
   last_end:=hi;
  end loop;
  select * into old from public.social_work_segments where segment_id=sid for update;
  if found then
   if old.user_id<>caller then raise exception 'This segment belongs to another account'; end if;
   if old.revision>rev then
    ack:=ack || jsonb_build_array(jsonb_build_object('segmentID',sid,'revision',old.revision)); continue;
   end if;
   if old.revision=rev then
    if old.started_at<>to_timestamp(first_time) or old.observed_through<>to_timestamp(last_time)
     or old.intervals<>item->'intervals' then raise exception 'Conflicting work revision'; end if;
    ack:=ack || jsonb_build_array(jsonb_build_object('segmentID',sid,'revision',rev)); continue;
   end if;
   -- Older clients replayed display timestamps truncated to whole seconds.
   -- Permit only restoring the missing fraction, with the entire unchanged
   -- recording translated by that same fraction. This cannot add work duration.
   legacy_shift:=first_time-extract(epoch from old.started_at)::double precision;
   repairs_rounded_start:=old.started_at=date_trunc('second',old.started_at)
    and legacy_shift>0 and legacy_shift<1
    and abs(last_time-extract(epoch from old.observed_through)::double precision-legacy_shift)<=0.000002
    and jsonb_array_length(old.intervals)=jsonb_array_length(item->'intervals')
    and not exists (
     select 1 from jsonb_array_elements(old.intervals) with ordinality as before(piece,n)
     join jsonb_array_elements(item->'intervals') with ordinality as after(piece,n) using(n)
     where abs((after.piece->>'start')::double precision-(before.piece->>'start')::double precision-legacy_shift)>0.000002
        or abs((after.piece->>'end')::double precision-(before.piece->>'end')::double precision-legacy_shift)>0.000002
    );
   if (old.started_at<>to_timestamp(first_time) and not repairs_rounded_start)
    or to_timestamp(last_time)<old.observed_through then
    raise exception 'Recording bounds cannot move backwards'; end if;
  end if;
  insert into public.social_work_segments values(sid,caller,rev,to_timestamp(first_time),to_timestamp(last_time),item->'intervals')
   on conflict(segment_id) do update set revision=excluded.revision,started_at=excluded.started_at,observed_through=excluded.observed_through,intervals=excluded.intervals;
  delete from public.social_work_days where segment_id=sid;
  delete from public.social_work_member_days where segment_id=sid;
  for piece in select value from jsonb_array_elements(item->'intervals') loop
   begin_at:=greatest(to_timestamp((piece->>'start')::double precision),activation);
   end_at:=to_timestamp((piece->>'end')::double precision); cursor_time:=begin_at;
   while cursor_time<end_at loop
    d:=(cursor_time at time zone zone)::date; boundary:=least(end_at,(d+1)::timestamp at time zone zone);
    insert into public.social_work_days values(sid,caller,d,extract(epoch from boundary-cursor_time))
     on conflict(segment_id,day) do update set seconds=public.social_work_days.seconds+excluded.seconds;
    cursor_time:=boundary;
   end loop;
   for m in select group_id,joined_at from public.social_members where user_id=caller and joined_at<end_at loop
    cursor_time:=greatest(begin_at,m.joined_at);
    while cursor_time<end_at loop
     d:=(cursor_time at time zone zone)::date; boundary:=least(end_at,(d+1)::timestamp at time zone zone);
     insert into public.social_work_member_days values(sid,m.group_id,caller,d,extract(epoch from boundary-cursor_time))
      on conflict(segment_id,group_id,day) do update set seconds=public.social_work_member_days.seconds+excluded.seconds;
     cursor_time:=boundary;
    end loop;
   end loop;
  end loop;
  ack:=ack || jsonb_build_array(jsonb_build_object('segmentID',sid,'revision',rev));
 end loop;
 insert into public.social_days(user_id,day,seconds,declared_seconds)
  select caller,day,sum(seconds),sum(seconds) from public.social_work_days where user_id=caller group by day
  on conflict(user_id,day) do update set
   seconds=greatest(0,public.social_days.seconds-public.social_days.declared_seconds)+excluded.declared_seconds,
   declared_seconds=excluded.declared_seconds;
 update public.social_days s set seconds=greatest(0,s.seconds-s.declared_seconds),declared_seconds=0
  where s.user_id=caller and s.declared_seconds>0 and not exists
   (select 1 from public.social_work_days w where w.user_id=caller and w.day=s.day);
 insert into public.social_member_days(group_id,user_id,day,seconds,declared_seconds)
  select group_id,caller,day,sum(seconds),sum(seconds) from public.social_work_member_days where user_id=caller group by group_id,day
  on conflict(group_id,user_id,day) do update set
   seconds=greatest(0,public.social_member_days.seconds-public.social_member_days.declared_seconds)+excluded.declared_seconds,
   declared_seconds=excluded.declared_seconds;
 update public.social_member_days s set seconds=greatest(0,s.seconds-s.declared_seconds),declared_seconds=0
  where s.user_id=caller and s.declared_seconds>0 and not exists
   (select 1 from public.social_work_member_days w where w.user_id=caller and w.group_id=s.group_id and w.day=s.day);
 return jsonb_build_object('version',1,'acknowledged',ack);
end;
$$;
revoke all on function public.sync_declared_work(jsonb,text) from public,anon;
grant execute on function public.sync_declared_work(jsonb,text) to authenticated;
