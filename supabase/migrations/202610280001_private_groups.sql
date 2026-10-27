-- Social summaries are separate from research. All access goes through the authenticated RPC.
create table public.social_accounts (
 user_id uuid primary key references auth.users on delete cascade,
 timezone text not null,
 activated_at timestamptz not null default now(),
 frozen date[] not null default '{}',
 join_window timestamptz not null default now(), join_attempts integer not null default 0
);
create table public.social_events (
 user_id uuid not null references public.social_accounts on delete cascade,
 id uuid not null, kind text not null check(kind in ('work','break')),
 ended_at timestamptz not null, seconds double precision not null check(seconds > 0 and seconds < 'Infinity'::double precision),
 primary key(user_id,id)
);
create table public.social_groups (
 id uuid primary key default gen_random_uuid(),
 owner uuid not null references auth.users on delete cascade,
 name text not null check(char_length(btrim(name)) between 1 and 60),
 code text not null unique default replace(gen_random_uuid()::text,'-','')
);
create table public.social_members (
 group_id uuid not null references public.social_groups on delete cascade,
 user_id uuid not null references public.social_accounts on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(group_id,user_id)
);
create table public.social_days (
 user_id uuid not null references public.social_accounts on delete cascade,
 day date not null, seconds double precision not null default 0, breaks text[] not null default '{}',
 primary key(user_id,day)
);
-- Qualification since membership is accumulated independently, including partial join days.
create table public.social_member_days (
 group_id uuid not null, user_id uuid not null, day date not null,
 seconds double precision not null default 0, healthy boolean not null default false,
 primary key(group_id,user_id,day),
 foreign key(group_id,user_id) references public.social_members on delete cascade
);
alter table public.social_accounts enable row level security;
alter table public.social_events enable row level security;
alter table public.social_groups enable row level security;
alter table public.social_members enable row level security;
alter table public.social_days enable row level security;
alter table public.social_member_days enable row level security;
revoke all on public.social_accounts,public.social_events,public.social_groups,public.social_members,public.social_days,public.social_member_days from anon,authenticated;

create function public.social_state(p_action text default 'sync', p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 caller uuid := auth.uid(); zone text; activation timestamptz; today date;
 e jsonb; eid uuid; kind text; ending timestamptz; starting timestamptz; duration double precision;
 cursor_time timestamptz; boundary timestamptz; d date; seconds_part double precision; m record;
 gid uuid; owner_id uuid; code_value text; attempt integer;
 frozen_days date[] := '{}'; used integer; alive boolean := false; last_frozen date; month_key text := '';
 day_row record; progress_days jsonb; groups_json jsonb; streak_cursor date;
begin
 if caller is null then raise exception 'Sign in to use groups'; end if;
 zone := coalesce(p_payload->>'timezone','UTC');
 if not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Invalid scoring timezone'; end if;
 insert into public.social_accounts(user_id,timezone,activated_at) values(caller,zone,least(now(),coalesce(to_timestamp((p_payload->>'activatedAt')::double precision),now()))) on conflict do nothing;
 select a.timezone,a.activated_at into zone,activation from public.social_accounts a where user_id=caller for update;
 today := (now() at time zone zone)::date;
 if jsonb_typeof(coalesce(p_payload->'events','[]')) <> 'array' or jsonb_array_length(coalesce(p_payload->'events','[]')) > 200 then raise exception 'Invalid progress batch'; end if;
 for e in select value from jsonb_array_elements(coalesce(p_payload->'events','[]')) loop
  eid := (e->>'id')::uuid; kind := e->>'kind'; duration := (e->>'seconds')::double precision;
  ending := to_timestamp((e->>'at')::double precision); starting := ending - duration * interval '1 second';
  if kind not in ('work','break') or duration is null or not (duration>0 and duration<'Infinity'::double precision)
     or (kind='work' and duration>604800) or ending is null or ending>now()+interval '5 minutes'  then raise exception 'Invalid progress summary'; end if;
  insert into public.social_events values(caller,eid,kind,ending,duration) on conflict do nothing;
  if not found then continue; end if;
  if kind='break' then
   if starting<activation then continue; end if;
   if duration<60 then continue; end if;
   d := (ending at time zone zone)::date;
   insert into public.social_days(user_id,day,breaks) values(caller,d,array[eid::text])
    on conflict(user_id,day) do update set breaks=public.social_days.breaks || excluded.breaks;
   for m in select * from public.social_members where user_id=caller and joined_at<=starting loop
    insert into public.social_member_days(group_id,user_id,day,healthy) values(m.group_id,caller,d,true)
     on conflict(group_id,user_id,day) do update set healthy=true;
   end loop;
  else
   cursor_time := greatest(starting,activation);
   while cursor_time<ending loop
    d := (cursor_time at time zone zone)::date;
    boundary := least(ending, ((d+1)::timestamp at time zone zone));
    seconds_part := extract(epoch from boundary-cursor_time);
    insert into public.social_days(user_id,day,seconds) values(caller,d,seconds_part)
     on conflict(user_id,day) do update set seconds=public.social_days.seconds+excluded.seconds;
    for m in select * from public.social_members where user_id=caller and joined_at<boundary loop
     insert into public.social_member_days(group_id,user_id,day,seconds)
      values(m.group_id,caller,d,extract(epoch from boundary-greatest(cursor_time,m.joined_at)))
      on conflict(group_id,user_id,day) do update set seconds=public.social_member_days.seconds+excluded.seconds;
    end loop;
    cursor_time := boundary;
   end loop;
  end if;
 end loop;
 -- Serialized, deterministic freeze decisions also reconcile delayed offline summaries.
 d := (activation at time zone zone)::date; used := 0;
 while d<today loop
  if month_key<>to_char(d,'YYYY-MM') then used:=0; month_key:=to_char(d,'YYYY-MM'); end if;
  if extract(isodow from d)<=5 then
   if coalesce((select seconds from public.social_days where user_id=caller and day=d),0)>=3600 then alive:=true;
   elsif alive and (last_frozen is null or last_frozen<>d-1) and used<3 then
    frozen_days:=array_append(frozen_days,d); used:=used+1; last_frozen:=d;
   else alive:=false;
   end if;
  end if;
  d:=d+1;
 end loop;
 update public.social_accounts set frozen=frozen_days where user_id=caller;

 if p_action='create' then
  if (select count(*) from public.social_members where user_id=caller)>=20 then raise exception 'You can join up to 20 groups'; end if;
  insert into public.social_groups(owner,name) values(caller,btrim(p_payload->>'name')) returning id into gid;
  insert into public.social_members(group_id,user_id) values(gid,caller);
 elsif p_action='join' then
  update public.social_accounts set join_attempts=case when join_window<now()-interval '1 hour' then 1 else join_attempts+1 end,
   join_window=case when join_window<now()-interval '1 hour' then now() else join_window end
   where user_id=caller returning join_attempts into attempt;
  if attempt>10 then return jsonb_build_object('error','Too many invite attempts. Try again in an hour.'); end if;
  select id into gid from public.social_groups where code=lower(btrim(p_payload->>'code')) for update;
  if gid is null then return jsonb_build_object('error','That invite code is invalid or has been reset.'); end if;
  if not exists(select 1 from public.social_members where group_id=gid and user_id=caller) then
   if (select count(*) from public.social_members where user_id=caller)>=20 or (select count(*) from public.social_members where group_id=gid)>=50 then
    return jsonb_build_object('error','This group or your group list is full.'); end if;
   insert into public.social_members(group_id,user_id) values(gid,caller);
  end if;
 elsif p_action in ('leave','delete','reset','remove') then
  gid:=(p_payload->>'group')::uuid;
  select owner into owner_id from public.social_groups g where g.id=gid for update;
  if not exists(select 1 from public.social_members where group_id=gid and user_id=caller) then raise exception 'Group membership required'; end if;
  if p_action='leave' then
   if owner_id=caller then raise exception 'Delete your group before leaving'; end if;
   delete from public.social_members where group_id=gid and user_id=caller;
  else
   if owner_id<>caller then raise exception 'Only the creator can manage this group'; end if;
   if p_action='delete' then delete from public.social_groups where id=gid;
   elsif p_action='reset' then update public.social_groups set code=replace(gen_random_uuid()::text,'-','') where id=gid;
   else
    if (p_payload->>'member')::uuid=caller then raise exception 'The creator cannot be removed'; end if;
    delete from public.social_members where group_id=gid and user_id=(p_payload->>'member')::uuid;
   end if;
  end if;
 elsif p_action<>'sync' then raise exception 'Unknown group action';
 end if;

 select coalesce(jsonb_object_agg(day::text,jsonb_build_object('workSeconds',seconds,'completedBreakIDs',to_jsonb(breaks))),'{}')
 into progress_days from public.social_days where user_id=caller;
 select coalesce(jsonb_agg(item order by item->>'name'),'[]') into groups_json from (
  select jsonb_build_object('id',g.id,'name',g.name,'owner',g.owner,'code',case when g.owner=caller then g.code else null end,
   'members',(select coalesce(jsonb_agg(jsonb_build_object('id',r.user_id,'name',r.name,'symbol',r.symbol,'color',r.color,
    'work',r.work,'habits',r.habits,'workRank',r.wrank,'habitsRank',r.hrank) order by r.name,r.user_id),'[]') from (
    select scores.*,rank() over(order by work desc) wrank,rank() over(order by habits desc) hrank from (
     select mm.user_id,coalesce(p.profile->>'name','Member') name,coalesce(p.profile->>'symbol','person.fill') symbol,
      coalesce(p.profile->>'color','teal') color,
      (select count(*) from public.social_member_days s where s.group_id=g.id and s.user_id=mm.user_id and s.seconds>=3600) work,
      (select count(*) from public.social_member_days s where s.group_id=g.id and s.user_id=mm.user_id and s.healthy) habits
     from public.social_members mm left join public.account_profiles p on p.user_id=mm.user_id where mm.group_id=g.id
    ) scores
   ) r)) item from public.social_groups g join public.social_members mine on mine.group_id=g.id and mine.user_id=caller
 ) items;
 return jsonb_build_object('timezone',zone,'progress',jsonb_build_object('version',1,'days',progress_days,
  'protectionStart',(activation at time zone zone)::date::text,'reconciledThrough',today::text,'frozenDays',to_jsonb(frozen_days)), 'groups',groups_json);
end;
$$;
revoke all on function public.social_state(text,jsonb) from public,anon;
grant execute on function public.social_state(text,jsonb) to authenticated;
