-- Synthetic users and groups exist only within this rolled-back transaction.
begin;
do $$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 gid uuid; iid uuid; state jsonb; inbox jsonb; denied boolean:=false;
 mail text:=gen_random_uuid()::text || '@example.invalid';
begin
 insert into auth.users(id,email) values(a,a::text || '@example.invalid'),(b,mail),(c,c::text || '@example.invalid');
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.social_state('create','{"timezone":"UTC","name":"Synthetic invitation verification"}');
 if state->>'groupFeaturesVersion'<>'2' then raise exception 'Feature capability missing'; end if;
 gid:=(state->'groups'->0->>'id')::uuid;
 perform public.social_state('invite',jsonb_build_object('timezone','UTC','group',gid,'email',mail));
 perform public.social_state('invite',jsonb_build_object('timezone','UTC','group',gid,'email',mail));
 perform set_config('request.jwt.claim.sub',b::text,true);
 inbox:=public.group_invitations();
 if jsonb_array_length(inbox)<>1 then raise exception 'Inbox delivery or deduplication failed'; end if;
 iid:=(inbox->0->>'id')::uuid;
 if exists(select 1 from public.social_accounts where user_id=b) then raise exception 'Inbox enabled sharing'; end if;
 perform set_config('request.jwt.claim.sub',c::text,true);
 if public.group_invitations()<>'[]'::jsonb then raise exception 'Inbox leaked'; end if;
 perform public.decline_group_invitation(iid);
 state:=public.social_state('accept',jsonb_build_object('timezone','UTC','invitation',iid));
 if not state ? 'error' then raise exception 'Wrong recipient accepted'; end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 if jsonb_array_length(public.group_invitations())<>1 then raise exception 'Wrong recipient declined'; end if;
 perform public.decline_group_invitation(iid);
 if public.group_invitations()<>'[]'::jsonb then raise exception 'Decline failed'; end if;
 if exists(select 1 from public.social_accounts where user_id=b) then raise exception 'Decline enabled sharing'; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.social_state('invite',jsonb_build_object('timezone','UTC','group',gid,'email',mail));
 perform set_config('request.jwt.claim.sub',b::text,true);
 inbox:=public.group_invitations(); iid:=(inbox->0->>'id')::uuid;
 state:=public.social_state('accept',jsonb_build_object('timezone','UTC','invitation',iid));
 if state ? 'error' or jsonb_array_length(state->'groups'->0->'members')<>2 then raise exception 'Accept failed'; end if;
 begin
  perform public.social_state('edit',jsonb_build_object('timezone','UTC','group',gid,'name','Unauthorized edit'));
 exception when raise_exception then denied:=true;
 end;
 if not denied then raise exception 'Non-admin edited group'; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.social_state('edit',jsonb_build_object('timezone','UTC','group',gid,'name','Updated group','description','Routine'));
 if state->'groups'->0->>'description'<>'Routine' then raise exception 'Edit failed'; end if;
 state:=public.social_state('transfer',jsonb_build_object('timezone','UTC','group',gid,'member',b));
 if (state->'groups'->0->>'owner')::uuid<>b then raise exception 'Transfer failed'; end if;
 if state->'groups'->0->>'code' is not null then raise exception 'Former admin retained code'; end if;
 denied:=false;
 begin
  perform public.social_state('remove',jsonb_build_object('timezone','UTC','group',gid,'member',b));
 exception when raise_exception then denied:=true;
 end;
 if not denied then raise exception 'Former admin retained removal permission'; end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 state:=public.social_state('remove',jsonb_build_object('timezone','UTC','group',gid,'member',a));
 if jsonb_array_length(state->'groups'->0->'members')<>1 then raise exception 'New admin removal failed'; end if;
 update public.social_members set joined_at='2026-10-19' where group_id=gid;
 insert into public.social_member_days(group_id,user_id,day,healthy) values(gid,b,'2026-10-19',true);
 if (select streak from public.social_group_habit_streak(b,gid,'2026-10-22T16:00Z'))<>0 then
  raise exception 'Healthy-habit streak did not reset'; end if;
 perform set_config('focusfix.invitation_live_checks','passed',true);
end $$;
select current_setting('focusfix.invitation_live_checks',true)='passed' as invitation_admin_and_habit_checks_passed;
rollback;
