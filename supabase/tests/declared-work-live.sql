-- Synthetic fixtures only; all writes roll back. Safe for the project SQL editor.
begin;
set local statement_timeout='30s';
create temporary table work_check (a uuid,b uuid,g uuid,s uuid,t double precision) on commit drop;
insert into work_check values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),extract(epoch from date_trunc('day',now())-interval '2 days'+interval '12 hours'));
grant select on work_check to authenticated;
insert into auth.users(id,email) select a,'work-a@example.invalid' from work_check union all select b,'work-b@example.invalid' from work_check;
insert into public.account_profiles(user_id,profile) select a,'{"name":"Work A","symbol":"leaf.fill","color":"teal","photo":"PRIVATE"}'::jsonb from work_check;
insert into public.social_accounts(user_id,timezone,activated_at) select a,'UTC',to_timestamp(t-7200) from work_check union all select b,'UTC',to_timestamp(t-7200) from work_check;
insert into public.social_groups(id,owner,name) select g,a,'Rollback work check' from work_check;
insert into public.social_members(group_id,user_id,joined_at) select g,a,to_timestamp(t-3600) from work_check union all select g,b,to_timestamp(t+1800) from work_check;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select a::text from work_check),true);
do $$ declare c record; payload jsonb; answer jsonb; state jsonb; begin
 select * into c from work_check;
 if has_table_privilege(current_user,'public.social_work_segments','SELECT') or has_function_privilege(current_user,'public.social_state_member_groups(text,jsonb)','EXECUTE') then raise exception 'Private helper exposed'; end if;
 payload:=jsonb_build_array(jsonb_build_object('ownerID',c.a,'segmentID',c.s,'contractVersion',2,'revision',1,'startedAt',c.t,'observedThrough',c.t+3600,'intervals',jsonb_build_array(jsonb_build_object('start',c.t,'end',c.t+3600))));
 answer:=public.sync_declared_work(payload,'UTC');
 perform public.sync_declared_work(payload,'UTC');
 state:=public.social_state();
 if (state->>'declaredWorkSyncVersion')::int<>1 or (state->'progress'->'days'->to_char(to_timestamp(c.t),'YYYY-MM-DD')->>'workSeconds')::numeric<>3600 then raise exception 'Work not synced exactly once'; end if;
 if (select (m->>'work')::int from jsonb_array_elements(state->'groups'->0->'members') m where m->>'id'=c.a::text)<>1 then raise exception 'Group work did not update'; end if;
 if state::text like '%PRIVATE%' or state::text like '%photo%' then raise exception 'Private photo exposed'; end if;
 payload:=jsonb_set(jsonb_set(payload,'{0,revision}','2'),'{0,intervals}','[]');
 perform public.sync_declared_work(payload,'UTC');
 state:=public.social_state();
 if (state->'progress'->'days'->to_char(to_timestamp(c.t),'YYYY-MM-DD')->>'workSeconds')::numeric<>0 then raise exception 'Correction failed'; end if;
 -- Older retries cannot restore deleted credit; same revision cannot change its contents.
 perform public.sync_declared_work(jsonb_set(payload,'{0,revision}','1'),'UTC');
 begin
  perform public.sync_declared_work(jsonb_set(payload,'{0,intervals}',jsonb_build_array(jsonb_build_object('start',c.t,'end',c.t+1))),'UTC');
  raise exception 'Conflicting revision accepted' using errcode='P0002';
 exception when raise_exception then if sqlerrm<>'Conflicting work revision' then raise; end if; end;
 begin
  perform public.sync_declared_work(payload,'Asia/Tokyo');
  raise exception 'Wrong timezone accepted' using errcode='P0002';
 exception when raise_exception then if sqlerrm<>'Scoring timezone mismatch' then raise; end if; end;
end $$;
reset role;
-- Preserve existing work/break credit when replacing only this recording's work.
insert into public.social_days(user_id,day,seconds,breaks) select a,to_timestamp(t)::date,3600,array['legacy-break'] from work_check on conflict(user_id,day) do update set seconds=3600,breaks=array['legacy-break'];
update public.account_profiles set profile=profile||'{"groupPhoto":"U0hBUkVE"}'::jsonb where user_id=(select a from work_check);
set local role authenticated;
do $$ declare c record; payload jsonb; state jsonb; begin
 select * into c from work_check;
 payload:=jsonb_build_array(jsonb_build_object('ownerID',c.a,'segmentID',c.s,'contractVersion',2,'revision',3,'startedAt',c.t,'observedThrough',c.t+3600,'intervals',jsonb_build_array(jsonb_build_object('start',c.t,'end',c.t+3600))));
 perform public.sync_declared_work(payload,'UTC');
 state:=public.social_state();
 if (state->'progress'->'days'->to_char(to_timestamp(c.t),'YYYY-MM-DD')->>'workSeconds')::numeric<>7200 then raise exception 'Legacy work was lost'; end if;
 if not(state::text like '%U0hBUkVE%') or state::text like '%PRIVATE%' then raise exception 'Opted-in thumbnail failed'; end if;
 payload:=jsonb_set(jsonb_set(payload,'{0,revision}','4'),'{0,intervals}','[]');
 perform public.sync_declared_work(payload,'UTC');
 state:=public.social_state();
 if (state->'progress'->'days'->to_char(to_timestamp(c.t),'YYYY-MM-DD')->>'workSeconds')::numeric<>3600 or not(state::text like '%legacy-break%') then raise exception 'Correction removed legacy work or breaks'; end if;
end $$;
select set_config('request.jwt.claim.sub',(select b::text from work_check),true);
do $$ declare c record; payload jsonb; begin
 select * into c from work_check;
 payload:=jsonb_build_array(jsonb_build_object('ownerID',c.b,'segmentID',c.s,'contractVersion',2,'revision',5,'startedAt',c.t,'observedThrough',c.t+3600,'intervals','[]'::jsonb));
 begin
  perform public.sync_declared_work(payload,'UTC');
  raise exception 'Cross-account overwrite accepted' using errcode='P0002';
 exception when raise_exception then if sqlerrm<>'This segment belongs to another account' then raise; end if; end;
 payload:=jsonb_set(jsonb_set(payload,'{0,segmentID}',to_jsonb(gen_random_uuid()::text)),'{0,intervals}',jsonb_build_array(jsonb_build_object('start',c.t,'end',c.t+3600)));
 perform public.sync_declared_work(payload,'UTC');
end $$;
reset role;
do $$ declare c record; begin
 select * into c from work_check;
 if (select seconds from public.social_work_member_days where user_id=c.b and group_id=c.g)<>1800 then raise exception 'Pre-join work credited'; end if;
 update public.account_profiles set profile=profile-'groupPhoto' where user_id=c.a;
end $$;
set local role authenticated;
do $$ begin
 if public.social_state()::text like '%U0hBUkVE%' then raise exception 'Photo opt-out failed'; end if;
end $$;
reset role;
rollback;
select true as declared_work_retries_corrections_ownership_membership_and_photo_checks_passed;
