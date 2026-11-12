-- Replace only new recording contributions; preserve all legacy work and break credit.
alter table public.social_days add column declared_seconds double precision not null default 0 check(declared_seconds>=0);
alter table public.social_member_days add column declared_seconds double precision not null default 0 check(declared_seconds>=0);
create table public.social_work_segments (
 segment_id uuid primary key, user_id uuid not null references public.social_accounts on delete cascade,
 revision integer not null check(revision>0), started_at timestamptz not null,
 observed_through timestamptz not null, intervals jsonb not null
);
create table public.social_work_days (
 segment_id uuid not null references public.social_work_segments on delete cascade,
 user_id uuid not null references public.social_accounts on delete cascade,
 day date not null, seconds double precision not null check(seconds>0 and seconds<'Infinity'::double precision),
 primary key(segment_id,day)
);
create table public.social_work_member_days (
 segment_id uuid not null references public.social_work_segments on delete cascade,
 group_id uuid not null, user_id uuid not null, day date not null,
 seconds double precision not null check(seconds>0 and seconds<'Infinity'::double precision),
 primary key(segment_id,group_id,day), foreign key(group_id,user_id) references public.social_members on delete cascade
);
alter table public.social_work_segments enable row level security;
alter table public.social_work_days enable row level security;
alter table public.social_work_member_days enable row level security;
revoke all on public.social_work_segments,public.social_work_days,public.social_work_member_days from public,anon,authenticated;
create function public.sync_declared_work(p_segments jsonb,p_timezone text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 caller uuid:=auth.uid(); zone text; activation timestamptz; item jsonb; piece jsonb;
 sid uuid; rev integer; first_time double precision; last_time double precision;
 lo double precision; hi double precision; last_end double precision; old public.social_work_segments%rowtype;
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
   if old.started_at<>to_timestamp(first_time) or to_timestamp(last_time)<old.observed_through then
    raise exception 'Recording bounds cannot move backwards'; end if;
  end if;
  insert into public.social_work_segments values(sid,caller,rev,to_timestamp(first_time),to_timestamp(last_time),item->'intervals')
   on conflict(segment_id) do update set revision=excluded.revision,observed_through=excluded.observed_through,intervals=excluded.intervals;
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
-- Only newly opted-in thumbnails are shared; existing private photos remain private.
alter table public.account_profiles drop constraint bounded_profile;
alter table public.account_profiles add constraint bounded_profile check (
 jsonb_typeof(profile)='object' and profile ?& array['name','symbol','color']
 and (profile-array['name','symbol','color','photo','groupPhoto'])='{}'::jsonb
 and jsonb_typeof(profile->'name')='string' and jsonb_typeof(profile->'symbol')='string'
 and jsonb_typeof(profile->'color')='string' and char_length(btrim(profile->>'name')) between 1 and 40
 and profile->>'symbol' in ('person.fill','leaf.fill','sun.max.fill','moon.stars.fill','bolt.fill','book.fill')
 and profile->>'color' in ('teal','blue','purple','orange','pink') and octet_length(profile::text)<=1500000
 and (not(profile ? 'groupPhoto') or (jsonb_typeof(profile->'groupPhoto')='string'
  and length(decode(profile->>'groupPhoto','base64')) between 1 and 32768))
);
alter function public.social_state(text,jsonb) rename to social_state_member_groups;
revoke all on function public.social_state_member_groups(text,jsonb) from public,anon,authenticated;
create function public.social_state(p_action text default 'sync',p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare state jsonb; groups_json jsonb;
begin
 state:=public.social_state_member_groups(p_action,p_payload);
 if state ? 'error' then return state; end if;
 select coalesce(jsonb_agg(g || jsonb_build_object('members',(
  select coalesce(jsonb_agg(member || jsonb_strip_nulls(jsonb_build_object('photo',(
   select profile->>'groupPhoto' from public.account_profiles where user_id=(member->>'id')::uuid
  ))) order by member->>'name',member->>'id'),'[]'::jsonb) from jsonb_array_elements(g->'members') member
 )) order by g->>'name'),'[]'::jsonb) into groups_json from jsonb_array_elements(state->'groups') g;
 return state || jsonb_build_object('groups',groups_json,'declaredWorkSyncVersion',1);
end;
$$;
revoke all on function public.social_state(text,jsonb) from public,anon;
grant execute on function public.social_state(text,jsonb) to authenticated;
