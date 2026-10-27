-- Fifty includes the creator; fixture-only transaction never changes persisted users.
begin;
create temporary table capacity_context(gid uuid, code text) on commit drop;
insert into capacity_context values(null,null);
grant select,update on capacity_context to authenticated;
insert into auth.users(id,email)
select ('d1d6cb83-7057-4bc0-955f-'||lpad(i::text,12,'0'))::uuid,'capacity-'||i||'@example.invalid' from generate_series(1,51) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1d6cb83-7057-4bc0-955f-000000000001',true);
do $$ declare state jsonb; begin
 state:=public.social_state('create','{"name":"Capacity fixture","timezone":"UTC"}');
 update pg_temp.capacity_context set gid=(state->'groups'->0->>'id')::uuid,code=state->'groups'->0->>'code';
end $$;
reset role;
insert into public.social_accounts(user_id,timezone)
select ('d1d6cb83-7057-4bc0-955f-'||lpad(i::text,12,'0'))::uuid,'UTC' from generate_series(2,49) i;
insert into public.social_members(group_id,user_id)
select c.gid,('d1d6cb83-7057-4bc0-955f-'||lpad(i::text,12,'0'))::uuid from capacity_context c cross join generate_series(2,49) i;
do $$ begin
 if (select count(*) from public.social_members m join capacity_context c on m.group_id=c.gid)<>49 then raise exception '49-person fixture failed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1d6cb83-7057-4bc0-955f-000000000050',true);
do $$ declare state jsonb; begin
 state:=public.social_state('join',jsonb_build_object('code',(select code from pg_temp.capacity_context)));
 if state ? 'error' or jsonb_array_length(state->'groups'->0->'members')<>50 then raise exception '50th person was rejected'; end if;
end $$;
select set_config('request.jwt.claim.sub','d1d6cb83-7057-4bc0-955f-000000000051',true);
do $$ declare state jsonb; begin
 state:=public.social_state('join',jsonb_build_object('code',(select code from pg_temp.capacity_context)));
 if not (state ? 'error') or state->>'error' not like '%full%' then raise exception '51st person was allowed'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.social_members m join capacity_context c on m.group_id=c.gid)<>50 then raise exception 'Capacity changed after rejected join'; end if;
end $$;
rollback;
