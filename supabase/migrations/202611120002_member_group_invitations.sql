-- Every current member can invite. Editing, removal and transfer remain admin-only.
create or replace function public.social_state(p_action text default 'sync', p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 caller uuid:=auth.uid(); state jsonb; gid uuid; admin_id uuid; target uuid; invitation uuid;
 title text; details text; groups_json jsonb;
begin
 -- Preserve validation, event deduplication, account serialization and existing clients.
 state:=public.social_state_work_streaks(case when p_action in ('invite','accept','decline','edit','transfer') then 'sync' else p_action end,p_payload);
 if state ? 'error' then return state; end if;
 if p_action in ('accept','decline') then
  invitation:=(p_payload->>'invitation')::uuid;
  select group_id into gid from public.social_invitations where id=invitation and recipient=caller;
  if gid is null then return jsonb_build_object('error','This invitation is no longer available.'); end if;
  -- Serialize acceptance with joins, removals, deletion and admin transfer.
  perform 1 from public.social_groups where id=gid for update;
  perform 1 from public.social_invitations where id=invitation and recipient=caller
   and created_at>now()-interval '30 days' for update;
  if not found then return jsonb_build_object('error','This invitation has expired or was withdrawn.'); end if;
  if p_action='accept' and not exists(select 1 from public.social_members where group_id=gid and user_id=caller) then
   if (select count(*) from public.social_members where group_id=gid)>=50 or
      (select count(*) from public.social_members where user_id=caller)>=20 then
    return jsonb_build_object('error','This group or your group list is full.'); end if;
   insert into public.social_members(group_id,user_id) values(gid,caller);
  end if;
  delete from public.social_invitations where id=invitation and recipient=caller;
 elsif p_action in ('invite','edit','transfer') then
  gid:=(p_payload->>'group')::uuid;
  select owner into admin_id from public.social_groups where id=gid for update;
  if p_action='invite' then
   if not exists(select 1 from public.social_members where group_id=gid and user_id=caller) then
    raise exception 'Group membership required to invite people'; end if;
  elsif admin_id is distinct from caller then raise exception 'Only the group admin can do this'; end if;
  if p_action='invite' then
   if (select count(*) from public.social_members where group_id=gid)>=50 then
    return jsonb_build_object('error','This group is full.'); end if;
   if (select count(*) from public.social_invitations where group_id=gid and created_at>now()-interval '30 days')>=100 then
    return jsonb_build_object('error','This group has too many pending invitations.'); end if;
   select id into target from auth.users where lower(email)=lower(btrim(p_payload->>'email'));
   if target is not null and target<>caller and not exists(select 1 from public.social_members where group_id=gid and user_id=target) then
    insert into public.social_invitations(group_id,recipient,invited_by) values(gid,target,caller)
     on conflict(group_id,recipient) do update set invited_by=excluded.invited_by,created_at=now();
   end if;
  elsif p_action='edit' then
   title:=btrim(p_payload->>'name'); details:=btrim(coalesce(p_payload->>'description',''));
   if title is null or char_length(title) not between 1 and 60 or char_length(details)>300 then
    return jsonb_build_object('error','Use a name of 1–60 characters and a description up to 300 characters.'); end if;
   update public.social_groups set name=title,description=details where id=gid;
  else
   target:=(p_payload->>'member')::uuid;
   if not exists(select 1 from public.social_members where group_id=gid and user_id=target) then
    raise exception 'Choose a current group member as admin'; end if;
   update public.social_groups set owner=target where id=gid;
  end if;
 end if;
 if p_action in ('invite','accept','decline','edit','transfer') then
  state:=public.social_state_work_streaks('sync',p_payload - 'events');
 end if;
 select coalesce(jsonb_agg(g || jsonb_build_object('description',(select description from public.social_groups where id=(g->>'id')::uuid),
  'members',(select coalesce(jsonb_agg(member || jsonb_build_object('habitsStreak',streak,'habitsStreakFrozen',frozen,'habitsStreakRank',streak_rank)
   order by member->>'name',member->>'id'),'[]'::jsonb) from (
    select member,h.streak,h.frozen,rank() over(order by h.streak desc) streak_rank
    from jsonb_array_elements(g->'members') member
    cross join lateral public.social_group_habit_streak((member->>'id')::uuid,(g->>'id')::uuid,now()) h
   ) scored)) order by g->>'name'),'[]'::jsonb) into groups_json from jsonb_array_elements(state->'groups') g;
 return state || jsonb_build_object('groups',groups_json,'invitations',public.group_invitations(),'groupFeaturesVersion',2);
end;
$$;

create or replace function public.group_invitations() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to view invitations'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'groupID',g.id,'groupName',g.name,
  'inviterName',coalesce(p.profile->>'name','Group member')) order by i.created_at desc)
 from public.social_invitations i join public.social_groups g on g.id=i.group_id
 left join public.account_profiles p on p.user_id=i.invited_by
 where i.recipient=auth.uid() and i.created_at>now()-interval '30 days'
 and not exists(select 1 from public.social_members m where m.group_id=i.group_id and m.user_id=auth.uid())), '[]'::jsonb);
end;
$$;
