-- FF: SOCIAL SYNC V2. One atomic work upload + progress delta + optional group snapshot.
-- Existing clients keep the original full response. No recording or history is deleted.
-- Group reads must not repeatedly decompress the private full-size photo to read a name.
-- Stored generated metadata stays consistent for both old and new profile writers.
alter table public.account_profiles
 add column display_name text generated always as (profile->>'name') stored,
 add column avatar_symbol text generated always as (profile->>'symbol') stored,
 add column avatar_color text generated always as (profile->>'color') stored,
 add column group_photo_version text generated always as (md5(profile->>'groupPhoto')) stored;

create sequence public.social_progress_revision;
revoke all on sequence public.social_progress_revision from public,anon,authenticated;
create table public.social_progress_changes (
 user_id uuid not null references public.social_accounts on delete cascade,
 day date not null, revision bigint not null,
 primary key(user_id,day)
);
create index social_progress_changes_cursor on public.social_progress_changes(user_id,revision);
alter table public.social_progress_changes enable row level security;
revoke all on public.social_progress_changes from public,anon,authenticated;
insert into public.social_progress_changes select user_id,day,nextval('public.social_progress_revision') from public.social_days;

create function public.track_social_progress_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare owner_id uuid; changed_day date;
begin
 if TG_OP='UPDATE' and new.seconds is not distinct from old.seconds and new.breaks is not distinct from old.breaks then return new; end if;
 if TG_OP='DELETE' then owner_id:=old.user_id; changed_day:=old.day;
 else owner_id:=new.user_id; changed_day:=new.day; end if;
 -- Allocate the revision after the account lock so a later cursor cannot skip a
 -- concurrent committed correction for this account. Cascading account deletion is exempt.
 perform 1 from public.social_accounts where user_id=owner_id for update;
 if found then
  insert into public.social_progress_changes values(owner_id,changed_day,nextval('public.social_progress_revision'))
  on conflict(user_id,day) do update set revision=excluded.revision;
 end if;
 if TG_OP='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.track_social_progress_change() from public,anon,authenticated;
create trigger social_progress_change after insert or update or delete on public.social_days
 for each row execute function public.track_social_progress_change();

create table public.social_freeze_cache (
 user_id uuid primary key references public.social_accounts on delete cascade,
 scoring_day date not null, activation timestamptz not null, revision bigint not null
);
alter table public.social_freeze_cache enable row level security;
revoke all on public.social_freeze_cache from public,anon,authenticated;
create function public.social_freezes_current(owner_id uuid,activation_time timestamptz,zone text) returns boolean
language sql volatile set search_path='' as $$
 select exists(select 1 from public.social_freeze_cache c where c.user_id=owner_id
 and c.scoring_day=(now() at time zone zone)::date and c.activation=activation_time
 and c.revision=coalesce((select max(revision) from public.social_progress_changes where user_id=owner_id),0));
$$;
revoke all on function public.social_freezes_current(uuid,timestamptz,text) from public,anon,authenticated;

-- Patch the known ingestion helper rather than copying or bypassing its access,
-- join-time scoring, freeze, deduplication and group-administration rules.
do $migration$
declare definition text:=pg_get_functiondef('public.social_state_daily_points(text,jsonb)'::regprocedure);
 history_query text:=$old$into progress_days from public.social_days where user_id=caller;$old$;
 group_query text:=$old$ select coalesce(jsonb_agg(item order by item->>'name'),'[]') into groups_json from ($old$;
 group_end text:=$old$ ) items;$old$;
 freeze_start text:=$old$ d := (activation at time zone zone)::date; used := 0;$old$;
 freeze_end text:=$old$ update public.social_accounts set frozen=frozen_days where user_id=caller;$old$;
begin
 if position(history_query in definition)=0 or position(group_query in definition)=0 or position(group_end in definition)=0
 or position(freeze_start in definition)=0 or position(freeze_end in definition)=0 then
  raise exception 'Unexpected social ingestion helper; review compact sync migration'; end if;
 definition:=replace(definition,history_query,$new$into progress_days from public.social_days s where s.user_id=caller
 and (coalesce(p_payload->>'syncVersion','')<>'2' or not (p_payload ? 'progressRevision') or exists
 (select 1 from public.social_progress_changes c where c.user_id=s.user_id and c.day=s.day
 and c.revision>(p_payload->>'progressRevision')::bigint));$new$);
 definition:=replace(definition,group_query,$new$ if coalesce(p_payload->>'syncVersion','')<>'2' or coalesce((p_payload->>'includeGroups')::boolean,true) then
 select coalesce(jsonb_agg(item order by item->>'name'),'[]') into groups_json from ($new$);
 definition:=replace(definition,group_end,$new$ ) items;
 else groups_json:='[]'::jsonb; end if;$new$);
 definition:=replace(definition,freeze_start,$new$ if not public.social_freezes_current(caller,activation,zone) then
 d := (activation at time zone zone)::date; used := 0;$new$);
 definition:=replace(definition,freeze_end,$new$ update public.social_accounts set frozen=frozen_days where user_id=caller;
 insert into public.social_freeze_cache values(caller,today,activation,
 coalesce((select max(revision) from public.social_progress_changes where user_id=caller),0))
 on conflict(user_id) do update set scoring_day=excluded.scoring_day,activation=excluded.activation,revision=excluded.revision;
 else select a.frozen into frozen_days from public.social_accounts a where user_id=caller; end if;$new$);
 definition:=replace(definition,$old$p.profile->>'name'$old$,'p.display_name');
 definition:=replace(definition,$old$p.profile->>'symbol'$old$,'p.avatar_symbol');
 definition:=replace(definition,$old$p.profile->>'color'$old$,'p.avatar_color');
 execute definition;
end;
$migration$;

create or replace function public.social_state(p_action text default 'sync',p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 caller uuid:=auth.uid(); state jsonb; canonical_groups jsonb; response_groups jsonb;
 compact boolean:=coalesce(p_payload->>'syncVersion','')='2'; wants_groups boolean;
 revision bigint; cursor_value bigint; group_version text; removed_days jsonb:='[]';
 ack jsonb:='[]'; zone text;
begin
 if caller is null then raise exception 'Sign in to use groups'; end if;
 if compact then
  if octet_length(p_payload::text)>33554432 or jsonb_typeof(p_payload) is distinct from 'object'
  or jsonb_typeof(coalesce(p_payload->'photoVersions','{}')) is distinct from 'object' then raise exception 'Invalid sync request'; end if;
  if (select count(*) from jsonb_object_keys(coalesce(p_payload->'photoVersions','{}')))>1000 then raise exception 'Too many photo versions'; end if;
  zone:=coalesce(p_payload->>'timezone','UTC');
  if not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Invalid scoring timezone'; end if;
  insert into public.social_accounts(user_id,timezone,activated_at)
  values(caller,zone,least(now(),coalesce(to_timestamp((p_payload->>'activatedAt')::double precision),now()))) on conflict do nothing;
  perform 1 from public.social_accounts where user_id=caller for update;
  if jsonb_array_length(coalesce(p_payload->'segments','[]'))>0 then
   ack:=public.sync_declared_work(p_payload->'segments',zone)->'acknowledged';
  end if;
  select coalesce(max(c.revision),0) into revision from public.social_progress_changes c where user_id=caller;
  cursor_value:=(p_payload->>'progressRevision')::bigint;
  -- Missing, negative or future cursors receive a full repair snapshot.
  if cursor_value is null or cursor_value<0 or cursor_value>revision then
   p_payload:=p_payload-'progressRevision'; cursor_value:=null;
  end if;
  wants_groups:=p_action<>'sync' or coalesce((p_payload->>'includeGroups')::boolean,true);
  p_payload:=jsonb_set(p_payload,'{includeGroups}',to_jsonb(wants_groups));
 end if;
 state:=public.social_state_member_groups(p_action,p_payload);
 if state ? 'error' then return state; end if;
 -- The legacy response includes shared thumbnails as before. Compact clients receive
 -- versions and only images not already held in their account-scoped memory cache.
 select coalesce(jsonb_agg(g || jsonb_build_object('members',(
  select coalesce(jsonb_agg(member || case when compact then
   jsonb_build_object('photoVersion',p.group_photo_version)
   else jsonb_strip_nulls(jsonb_build_object('photo',p.profile->>'groupPhoto')) end
   order by member->>'name',member->>'id'),'[]')
  from jsonb_array_elements(g->'members') member
  left join public.account_profiles p on p.user_id=(member->>'id')::uuid
 )) order by g->>'name',g->>'id'),'[]') into canonical_groups from jsonb_array_elements(state->'groups') g;
 if not compact then
  return state || jsonb_build_object('groups',canonical_groups,'declaredWorkSyncVersion',1,'socialSyncVersion',2);
 end if;
 select coalesce(max(c.revision),0) into revision from public.social_progress_changes c where user_id=caller;
 if cursor_value is not null then
  select coalesce(jsonb_agg(c.day::text order by c.day),'[]') into removed_days from public.social_progress_changes c
  where c.user_id=caller and c.revision>cursor_value and not exists
   (select 1 from public.social_days d where d.user_id=c.user_id and d.day=c.day);
 end if;
 group_version:=md5(canonical_groups::text);
 if wants_groups and group_version is distinct from p_payload->>'groupVersion' then
  select coalesce(jsonb_agg(g || jsonb_build_object('members',(
   select coalesce(jsonb_agg(member || case when member->>'photoVersion' is not null
    and (p_payload->'photoVersions'->>(member->>'id')) is distinct from member->>'photoVersion'
    then jsonb_build_object('photo',(select profile->>'groupPhoto' from public.account_profiles where user_id=(member->>'id')::uuid))
    else '{}'::jsonb end order by member->>'name',member->>'id'),'[]') from jsonb_array_elements(g->'members') member
  )) order by g->>'name',g->>'id'),'[]') into response_groups from jsonb_array_elements(canonical_groups) g;
 else response_groups:='[]'; end if;
 return state || jsonb_build_object('groups',response_groups,'groupsIncluded',wants_groups and group_version is distinct from p_payload->>'groupVersion',
 'groupVersion',case when wants_groups then group_version end,'socialSyncVersion',2,'declaredWorkSyncVersion',1,
 'progressRevision',revision,'progressIsDelta',cursor_value is not null,'removedDays',removed_days,'acknowledgedWork',ack);
end;
$$;
revoke all on function public.social_state(text,jsonb) from public,anon;
grant execute on function public.social_state(text,jsonb) to authenticated;
