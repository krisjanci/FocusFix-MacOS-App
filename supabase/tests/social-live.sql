-- Synthetic live verification. Every fixture and mutation is rolled back.
-- Run as the project SQL editor's postgres role. No real credentials, email addresses or recordings are used.
begin;
set local statement_timeout = '30s';
create temporary table social_check_context (
 alice uuid, bob uuid, outsider uuid, gid uuid, invite text, replacement text, event_id uuid, at_time timestamptz
) on commit drop;
insert into social_check_context values (
 'e85fb9c6-914f-4a9e-b806-622169cb1e11', 'e85fb9c6-914f-4a9e-b806-622169cb1e12', 'e85fb9c6-914f-4a9e-b806-622169cb1e13',
 null,null,null,gen_random_uuid(),((now() at time zone 'UTC')::date - 1 + time '12:00') at time zone 'UTC'
);
create temporary table social_check_results(check_name text primary key, passed boolean not null) on commit drop;
grant select,update on social_check_context to authenticated;
grant select,insert on social_check_results to authenticated;
insert into auth.users(id,email) select alice,'social-check-a@example.invalid' from social_check_context
union all select bob,'social-check-b@example.invalid' from social_check_context
union all select outsider,'social-check-c@example.invalid' from social_check_context;
insert into public.account_profiles(user_id,profile)
select alice,'{"name":"Synthetic A","symbol":"leaf.fill","color":"teal","photo":"UFJJVkFURQ=="}'::jsonb from social_check_context
union all select bob,'{"name":"Synthetic B","symbol":"book.fill","color":"blue"}'::jsonb from social_check_context;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select alice::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; begin
 select * into c from pg_temp.social_check_context;
 state:=public.social_state('create',jsonb_build_object('name','FocusFix verification (rolled back)','timezone','UTC','activatedAt',extract(epoch from c.at_time-interval '4 hours')));
 update pg_temp.social_check_context set gid=(state->'groups'->0->>'id')::uuid,invite=state->'groups'->0->>'code';
 if length(state->'groups'->0->>'code')<>32 then raise exception 'Invite format failed'; end if;
 if has_table_privilege(current_user,'public.social_accounts','SELECT') or has_table_privilege(current_user,'public.social_events','INSERT') then raise exception 'Direct social access allowed'; end if;
 insert into pg_temp.social_check_results values('private authenticated RPC and invite creation',true);
end $$;
select set_config('request.jwt.claim.sub',(select bob::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; begin
 select * into c from pg_temp.social_check_context;
 state:=public.social_state('sync',jsonb_build_object('timezone','UTC','activatedAt',extract(epoch from c.at_time-interval '4 hours'),
 'events',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind','work','at',extract(epoch from c.at_time),'seconds',3600))));
 if jsonb_array_length(state->'groups')<>0 then raise exception 'Nonmember saw groups'; end if;
 state:=public.social_state('join',jsonb_build_object('code',c.invite));
 if state->'groups'->0->'code'<>'null'::jsonb or exists(select 1 from jsonb_array_elements(state->'groups'->0->'members') m where (m->>'work')::int<>0) then raise exception 'Join leaked history or invite'; end if;
 insert into pg_temp.social_check_results values('membership privacy and no historical group credit',true);
end $$;
reset role;
update public.social_members set joined_at=c.at_time-interval '2 hours' from social_check_context c where group_id=c.gid and user_id in(c.alice,c.bob);
set local role authenticated;
select set_config('request.jwt.claim.sub',(select bob::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; events jsonb; member jsonb; begin
 select * into c from pg_temp.social_check_context;
 events:=jsonb_build_array(jsonb_build_object('id',c.event_id,'kind','work','at',extract(epoch from c.at_time),'seconds',3599));
 state:=public.social_state('sync',jsonb_build_object('events',events));
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=c.bob::text;
 if (member->>'work')::int<>0 then raise exception 'Early work point'; end if;
 events:=events || jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind','work','at',extract(epoch from c.at_time),'seconds',1),
 jsonb_build_object('id',gen_random_uuid(),'kind','break','at',extract(epoch from c.at_time),'seconds',59.99));
 state:=public.social_state('sync',jsonb_build_object('events',events));
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=c.bob::text;
 if (member->>'work')::int<>1 or (member->>'habits')::int<>0 then raise exception 'Qualification boundary failed'; end if;
 events:=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind','break','at',extract(epoch from c.at_time),'seconds',60));
 state:=public.social_state('sync',jsonb_build_object('events',events || events));
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=c.bob::text;
 if (member->>'habits')::int<>1 then raise exception 'Healthy point failed'; end if;
 if (state->'progress'->'days'->((c.at_time at time zone 'UTC')::date::text)->>'workSeconds')::numeric<>7200 then raise exception 'Retry duplicated work'; end if;
 insert into pg_temp.social_check_results values('work and break thresholds with retry deduplication',true);
end $$;
select set_config('request.jwt.claim.sub',(select alice::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; begin
 select * into c from pg_temp.social_check_context;
 state:=public.social_state('sync',jsonb_build_object('events',jsonb_build_array(
 jsonb_build_object('id',gen_random_uuid(),'kind','work','at',extract(epoch from c.at_time),'seconds',3600),
 jsonb_build_object('id',gen_random_uuid(),'kind','break','at',extract(epoch from c.at_time),'seconds',60))));
 if exists(select 1 from jsonb_array_elements(state->'groups'->0->'members') m where (m->>'workRank')::int<>1 or (m->>'habitsRank')::int<>1) then raise exception 'Equal ranks failed'; end if;
 if (state->'groups')::text like '%photo%' or (state->'groups')::text like '%example.invalid%' then raise exception 'Private profile leaked'; end if;
 state:=public.social_state('reset',jsonb_build_object('group',c.gid));
 update pg_temp.social_check_context set replacement=state->'groups'->0->>'code';
 if state->'groups'->0->>'code'=c.invite then raise exception 'Invite rotation failed'; end if;
 insert into pg_temp.social_check_results values('equal ranks and photo-free member presentation',true);
end $$;
select set_config('request.jwt.claim.sub',(select outsider::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; i int; begin
 select * into c from pg_temp.social_check_context;
 state:=public.social_state();
 if jsonb_array_length(state->'groups')<>0 then raise exception 'Outsider read groups'; end if;
 begin
  perform public.social_state('remove',jsonb_build_object('group',c.gid,'member',c.bob));
  raise exception 'Outsider modified group' using errcode='P0002';
 exception when raise_exception then if sqlerrm<>'Group membership required' then raise; end if; end;
 for i in 1..10 loop
  state:=public.social_state('join',jsonb_build_object('code','invalid'));
  if state->>'error' not like '%invalid%' then raise exception 'Unexpected invite result'; end if;
 end loop;
 state:=public.social_state('join',jsonb_build_object('code',c.replacement));
 if state->>'error' not like '%Too many%' then raise exception 'Invite throttling failed'; end if;
 insert into pg_temp.social_check_results values('outsider isolation and persistent invite throttling',true);
end $$;
select set_config('request.jwt.claim.sub',(select bob::text from pg_temp.social_check_context),true);
do $$ declare c record; state jsonb; member jsonb; begin
 select * into c from pg_temp.social_check_context;
 perform public.social_state('leave',jsonb_build_object('group',c.gid));
 state:=public.social_state('join',jsonb_build_object('code',c.invite));
 if state->>'error' not like '%invalid%' then raise exception 'Revoked invite accepted'; end if;
 state:=public.social_state('join',jsonb_build_object('code',c.replacement));
 select value into member from jsonb_array_elements(state->'groups'->0->'members') where value->>'id'=c.bob::text;
 if (member->>'work')::int<>0 or (member->>'habits')::int<>0 then raise exception 'Rejoin restored score'; end if;
 insert into pg_temp.social_check_results values('revoked codes and fresh rejoin scores',true);
end $$;
reset role;
update public.social_accounts set activated_at='2026-01-01T00:00:00Z' where user_id=(select alice from social_check_context);
insert into public.social_days(user_id,day,seconds) select alice,d::date,3600 from social_check_context cross join unnest(array['2026-01-01','2026-01-05','2026-01-07','2026-01-09']) d;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select alice::text from pg_temp.social_check_context),true);
do $$ declare state jsonb; repeated jsonb; frozen text[]; begin
 state:=public.social_state('sync','{"timezone":"Asia/Tokyo"}');
 if state->>'timezone'<>'UTC' then raise exception 'Timezone changed across devices'; end if;
 select array_agg(value order by value) into frozen from jsonb_array_elements_text(state->'progress'->'frozenDays') where value like '2026-01%';
 if frozen<>array['2026-01-02','2026-01-06','2026-01-08'] then raise exception 'Monthly freeze decisions failed'; end if;
 repeated:=public.social_state();
 if state->'progress'->'frozenDays'<>repeated->'progress'->'frozenDays' then raise exception 'Repeated sync spent more tokens'; end if;
 insert into pg_temp.social_check_results values('stable timezone and idempotent monthly freeze limits',true);
end $$;
reset role;
select check_name,passed from social_check_results order by check_name;
rollback;
select not exists(select 1 from auth.users where id in('e85fb9c6-914f-4a9e-b806-622169cb1e11','e85fb9c6-914f-4a9e-b806-622169cb1e12','e85fb9c6-914f-4a9e-b806-622169cb1e13')) as synthetic_fixtures_rolled_back;
