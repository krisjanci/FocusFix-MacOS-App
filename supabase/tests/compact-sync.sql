-- Synthetic fixtures only. Exercises the actual migrations, never a live service.
begin;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 g uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); t double precision:=extract(epoch from current_date-interval '2 days'+interval '12 hours');
 original jsonb; first_state jsonb; answer jsonb; baseline jsonb; body jsonb; cursor_value bigint; version text;
 before_streak jsonb; after_streak jsonb; photo text:=repeat('QUJD',1000); day_key text:=to_char(to_timestamp(t),'YYYY-MM-DD');
begin
 insert into auth.users(id,email) values(a,'compact-a@example.invalid'),(b,'compact-b@example.invalid'),(outsider,'compact-out@example.invalid');
 insert into public.social_accounts(user_id,timezone,activated_at) values(a,'UTC',to_timestamp(t-86400)),(b,'UTC',to_timestamp(t-86400));
 insert into public.account_profiles(user_id,profile) values
 (a,jsonb_build_object('name','Compact A','symbol','leaf.fill','color','teal','photo','PRIVATE','groupPhoto',photo)),
 (b,'{"name":"Compact B","symbol":"leaf.fill","color":"teal"}');
 insert into public.social_groups(id,owner,name) values(g,a,'Compact group');
 insert into public.social_members(group_id,user_id,joined_at) values(g,a,to_timestamp(t-86400)),(g,b,to_timestamp(t-86400));
 insert into public.social_days(user_id,day,seconds) values(a,to_timestamp(t)::date,7200);
 insert into public.social_member_days(group_id,user_id,day,seconds,healthy) values(g,a,to_timestamp(t)::date,7200,true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 original:=public.social_state();
 if original->>'socialSyncVersion'<>'2' or not(original::text like '%'||photo||'%') then raise exception 'Legacy response changed'; end if;
 body:=jsonb_build_object('syncVersion',2,'timezone','UTC','includeGroups',true);
 first_state:=public.social_state('sync',body);
 if first_state->'progress' is distinct from original->'progress' or first_state->>'progressIsDelta'<>'false'
 or first_state->>'groupsIncluded'<>'true' or first_state::text like '%PRIVATE%' then raise exception 'Initial compact snapshot failed'; end if;
 cursor_value:=(first_state->>'progressRevision')::bigint; version:=first_state->>'groupVersion';
 body:=body||jsonb_build_object('progressRevision',cursor_value,'groupVersion',version,'photoVersions',jsonb_build_object(a::text,md5(photo)));
 answer:=public.social_state('sync',body);
 if answer->>'groupsIncluded'<>'false' or answer->'groups'<>'[]'::jsonb or answer->'progress'->'days'<>'{}'::jsonb
 or octet_length(answer::text)>=octet_length(first_state::text)/2 then raise exception 'Unchanged sync is not compact'; end if;
 -- A changed name sends a new group snapshot without retransmitting the cached image.
 update public.account_profiles set profile=jsonb_set(profile,'{name}','"Renamed"') where user_id=b;
 answer:=public.social_state('sync',body);
 if answer->>'groupsIncluded'<>'true' or answer::text like '%'||photo||'%' or not(answer::text like '%Renamed%')
 or not(answer::text like '%photoVersion%') then raise exception 'Versioned photo caching failed'; end if;
 -- Work is applied BEFORE scoring in the same request; a retry cannot add credit.
 body:=body||jsonb_build_object('segments',jsonb_build_array(jsonb_build_object('ownerID',a,'segmentID',sid,
 'contractVersion',2,'revision',1,'startedAt',t,'observedThrough',t+3600,
 'intervals',jsonb_build_array(jsonb_build_object('start',t,'end',t+3600)))));
 answer:=public.social_state('sync',body);
 if jsonb_array_length(answer->'acknowledgedWork')<>1 or (answer->'progress'->'days'->day_key->>'workSeconds')::int<>10800
 then raise exception 'Atomic work acknowledgement or delta failed'; end if;
 baseline:=answer;
 answer:=public.social_state('sync',body);
 if answer->'progress'->'days' is distinct from baseline->'progress'->'days' then raise exception 'Duplicate work credited twice'; end if;
 -- A delayed historical correction lowers credit and invalidates derived streak caches.
 body:=jsonb_set(jsonb_set(body,'{segments,0,revision}','2'),'{segments,0,intervals}','[]');
 answer:=public.social_state('sync',body);
 if (answer->'progress'->'days'->day_key->>'workSeconds')::int<>7200 then raise exception 'Backdated correction failed'; end if;
 -- Missing/future cursors repair fully; explicit day deletions have tombstones.
 answer:=public.social_state('sync',body||'{"progressRevision":9223372036854775807}');
 if answer->>'progressIsDelta'<>'false' or answer->'progress'->'days'='{}'::jsonb then raise exception 'Future cursor did not reset'; end if;
 cursor_value:=(answer->>'progressRevision')::bigint;
 delete from public.social_days where user_id=a and day=to_timestamp(t)::date;
 answer:=public.social_state('sync',jsonb_build_object('syncVersion',2,'timezone','UTC','includeGroups',false,'progressRevision',cursor_value));
 if answer->'removedDays'<>jsonb_build_array(day_key) or answer->>'groupsIncluded'<>'false' or answer->'groups'<>'[]'::jsonb then raise exception 'Deleted day/hidden groups failed'; end if;
 -- Activation changes invalidate freeze metadata even without any changed day.
 update public.social_accounts set activated_at=activated_at-interval '1 day' where user_id=a;
 perform public.social_state();
 if (select activation from public.social_freeze_cache where user_id=a) is distinct from
    (select activated_at from public.social_accounts where user_id=a) then raise exception 'Activation did not invalidate freeze cache'; end if;
 -- Photo revocation is reflected even if the client presents its old cache version.
 update public.account_profiles set profile=profile-'groupPhoto' where user_id=a;
 answer:=public.social_state('sync',body-'segments');
 if answer::text like '%'||photo||'%' or exists(select 1 from jsonb_array_elements(answer->'groups'->0->'members') m
 where m->>'id'=a::text and m->>'photoVersion' is not null) then raise exception 'Photo revocation failed'; end if;
 -- New private state must not become a public API or an outsider directory.
 if has_table_privilege('authenticated','public.social_progress_changes','SELECT')
 or has_table_privilege('authenticated','public.social_streak_cache','SELECT')
 or has_table_privilege('authenticated','public.social_freeze_cache','SELECT')
 or has_function_privilege('authenticated','public.social_cached_streak(uuid,uuid,timestamptz,text)','EXECUTE')
 or has_function_privilege('anon','public.social_state(text,jsonb)','EXECUTE') then raise exception 'Private scaling state exposed'; end if;
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 answer:=public.social_state('sync',body-'segments');
 if answer->'groups'<>'[]'::jsonb or answer::text like '%Compact group%' then raise exception 'Outsider saw group'; end if;
 -- Cached and reference scores agree after edits, membership changes and day rollover.
 for t in select extract(epoch from current_date+offset_day*interval '1 day') from generate_series(-2,2) offset_day loop
  select to_jsonb(s) into before_streak from public.social_group_work_streak_uncached(a,g,to_timestamp(t)) s;
  select to_jsonb(s) into after_streak from public.social_group_work_streak(a,g,to_timestamp(t)) s;
  if before_streak is distinct from after_streak then raise exception 'Cached work scoring differs'; end if;
  select to_jsonb(s) into before_streak from public.social_group_habit_streak_uncached(a,g,to_timestamp(t)) s;
  select to_jsonb(s) into after_streak from public.social_group_habit_streak(a,g,to_timestamp(t)) s;
  if before_streak is distinct from after_streak then raise exception 'Cached habits scoring differs'; end if;
 end loop;
 update public.social_member_days set seconds=0,healthy=false where user_id=a;
 if exists(select 1 from public.social_streak_cache where user_id=a) then raise exception 'Correction did not invalidate streak cache'; end if;
 perform public.social_group_work_streak(a,g,now());
 update public.social_members set joined_at=now() where group_id=g and user_id=a;
 if exists(select 1 from public.social_streak_cache where user_id=a) then raise exception 'Membership edit did not invalidate cache'; end if;
 delete from auth.users where id=a;
 if exists(select 1 from public.social_progress_changes where user_id=a) or exists(select 1 from public.social_freeze_cache where user_id=a)
 or exists(select 1 from public.social_streak_cache where user_id=a) then raise exception 'Account deletion left scaling state'; end if;
end;
$$;
rollback;
