-- FF: SOCIAL SCALING. Preserve segment revisions and all historical corrections,
-- but aggregate only dates touched by an actual replacement. Identical retries do no rebuild.
do $migration$
declare definition text:=pg_get_functiondef('public.sync_declared_work(jsonb,text)'::regprocedure);
 marker text:=$old$  delete from public.social_work_days where segment_id=sid;$old$;
 ack_marker text:=$old$  ack:=ack || jsonb_build_array(jsonb_build_object('segmentID',sid,'revision',rev));
 end loop;$old$;
begin
 if position(marker in definition)=0 or position(ack_marker in definition)=0
 or position('ack jsonb:=''[]''::jsonb;' in definition)=0 then
  raise exception 'Unexpected declared-work helper; review changed-day migration'; end if;
 definition:=replace(definition,'ack jsonb:=''[]''::jsonb;', 'affected_days date[]:=''{}''; ack jsonb:=''[]''::jsonb;');
 definition:=replace(definition,marker,$new$  affected_days:=affected_days || coalesce((select array_agg(day) from public.social_work_days where segment_id=sid),'{}'::date[]);
  delete from public.social_work_days where segment_id=sid;$new$);
 definition:=replace(definition,ack_marker,$new$  affected_days:=affected_days || coalesce((select array_agg(day) from public.social_work_days where segment_id=sid),'{}'::date[]);
  ack:=ack || jsonb_build_array(jsonb_build_object('segmentID',sid,'revision',rev));
 end loop;$new$);
 definition:=replace(definition,'from public.social_work_days where user_id=caller group by day',
 'from public.social_work_days where user_id=caller and day=any(affected_days) group by day');
 definition:=replace(definition,'from public.social_work_member_days where user_id=caller group by group_id,day',
 'from public.social_work_member_days where user_id=caller and day=any(affected_days) group by group_id,day');
 definition:=replace(definition,'where s.user_id=caller and s.declared_seconds>0 and not exists',
 'where s.user_id=caller and s.day=any(affected_days) and s.declared_seconds>0 and not exists');
 execute definition;
end;
$migration$;

-- Streaks depend on daily qualification, not changing seconds above the goal.
create or replace function public.invalidate_social_streak_cache() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and new.group_id=old.group_id and new.user_id=old.user_id and new.day=old.day
 and (new.seconds>=3600)=(old.seconds>=3600) and new.healthy=old.healthy then return new; end if;
 if TG_OP='UPDATE' and new is not distinct from old then return new; end if;
 if TG_OP<>'INSERT' then
  delete from public.social_streak_cache where group_id=old.group_id and user_id=old.user_id;
 end if;
 if TG_OP<>'DELETE' then
  delete from public.social_streak_cache where group_id=new.group_id and user_id=new.user_id;
  return new;
 end if;
 return old;
end;
$$;
-- Membership rows have no day/seconds fields, so use their own invalidation trigger.
create function public.invalidate_social_membership_streak_cache() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from public.social_streak_cache where group_id=old.group_id and user_id=old.user_id;
 return new;
end;
$$;
revoke all on function public.invalidate_social_membership_streak_cache() from public,anon,authenticated;
drop trigger social_membership_streak_cache on public.social_members;
create trigger social_membership_streak_cache after update on public.social_members
 for each row execute function public.invalidate_social_membership_streak_cache();

-- Progress cursors still advance for changed seconds and breaks, but freeze decisions
-- only need rebuilding at a qualification change, scoring-day rollover or activation edit.
create or replace function public.track_social_progress_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare owner_id uuid; changed_day date; qualification_changed boolean;
begin
 if TG_OP='UPDATE' and new.seconds is not distinct from old.seconds and new.breaks is not distinct from old.breaks then return new; end if;
 if TG_OP='DELETE' then
  owner_id:=old.user_id; changed_day:=old.day; qualification_changed:=old.seconds>=3600;
 elsif TG_OP='INSERT' then
  owner_id:=new.user_id; changed_day:=new.day; qualification_changed:=new.seconds>=3600;
 else
  owner_id:=new.user_id; changed_day:=new.day; qualification_changed:=(new.seconds>=3600)<>(old.seconds>=3600);
 end if;
 perform 1 from public.social_accounts where user_id=owner_id for update;
 if found then
  insert into public.social_progress_changes values(owner_id,changed_day,nextval('public.social_progress_revision'))
  on conflict(user_id,day) do update set revision=excluded.revision;
  if qualification_changed then delete from public.social_freeze_cache where user_id=owner_id; end if;
 end if;
 if TG_OP='DELETE' then return old; else return new; end if;
end;
$$;
create or replace function public.social_freezes_current(owner_id uuid,activation_time timestamptz,zone text) returns boolean
language sql volatile set search_path='' as $$
 select exists(select 1 from public.social_freeze_cache c where c.user_id=owner_id
 and c.scoring_day=(now() at time zone zone)::date and c.activation=activation_time);
$$;
