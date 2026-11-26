-- FF: SOCIAL SCALING. Additive: legacy RPCs and all scoring rules remain supported.
-- User-prefix indexes match replacement aggregation, membership lookup and cascades.
create index social_members_by_user on public.social_members(user_id,group_id);
create index social_work_days_by_user on public.social_work_days(user_id,day);
create index social_work_member_days_by_user on public.social_work_member_days(user_id,group_id,day);
create index social_work_member_days_by_membership on public.social_work_member_days(group_id,user_id,day);
create index social_work_segments_by_user on public.social_work_segments(user_id);
create index social_invitations_by_recipient on public.social_invitations(recipient,created_at);
create index social_groups_by_owner on public.social_groups(owner);

-- Only a derived cache. No history or deduplication records are discarded.
create table public.social_streak_cache (
 group_id uuid not null, user_id uuid not null,
 metric text not null check(metric in ('work','habits')),
 scoring_day date not null, scoring_timezone text not null, membership_started_at timestamptz not null,
 streak integer not null, frozen boolean not null,
 primary key(group_id,user_id,metric),
 foreign key(group_id,user_id) references public.social_members on delete cascade
);
alter table public.social_streak_cache enable row level security;
revoke all on public.social_streak_cache from public,anon,authenticated;

create function public.invalidate_social_streak_cache() returns trigger
language plpgsql security definer set search_path='' as $$
begin
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
revoke all on function public.invalidate_social_streak_cache() from public,anon,authenticated;
create trigger social_day_streak_cache after insert or update or delete on public.social_member_days
 for each row execute function public.invalidate_social_streak_cache();
create trigger social_membership_streak_cache after update on public.social_members
 for each row execute function public.invalidate_social_streak_cache();

alter function public.social_group_work_streak(uuid,uuid,timestamptz) rename to social_group_work_streak_uncached;
alter function public.social_group_habit_streak(uuid,uuid,timestamptz) rename to social_group_habit_streak_uncached;
-- The original private helpers remain the reference algorithm for backdated corrections.
create function public.social_cached_streak(member_id uuid,selected_group uuid,as_of timestamptz,selected_metric text)
returns table(streak integer,frozen boolean)
language plpgsql volatile set search_path='' as $$
declare zone text; joined timestamptz; today date; cached public.social_streak_cache; result_streak integer; result_frozen boolean;
begin
 select a.timezone,m.joined_at into zone,joined from public.social_members m
 join public.social_accounts a on a.user_id=m.user_id where m.group_id=selected_group and m.user_id=member_id;
 if joined is null then return query select 0,false; return; end if;
 today:=(as_of at time zone zone)::date;
 select * into cached from public.social_streak_cache c
 where c.group_id=selected_group and c.user_id=member_id and c.metric=selected_metric;
 if found and cached.scoring_day=today and cached.scoring_timezone=zone and cached.membership_started_at=joined then
  return query select cached.streak,cached.frozen; return;
 end if;
 if selected_metric='work' then
  select s.streak,s.frozen into result_streak,result_frozen from public.social_group_work_streak_uncached(member_id,selected_group,as_of) s;
 elsif selected_metric='habits' then
  select s.streak,s.frozen into result_streak,result_frozen from public.social_group_habit_streak_uncached(member_id,selected_group,as_of) s;
 else raise exception 'Unknown streak metric'; end if;
 insert into public.social_streak_cache values(selected_group,member_id,selected_metric,today,zone,joined,result_streak,result_frozen)
 on conflict(group_id,user_id,metric) do update set scoring_day=excluded.scoring_day,
 scoring_timezone=excluded.scoring_timezone,membership_started_at=excluded.membership_started_at,
 streak=excluded.streak,frozen=excluded.frozen;
 return query select result_streak,result_frozen;
end;
$$;
create function public.social_group_work_streak(member_id uuid,selected_group uuid,as_of timestamptz)
returns table(streak integer,frozen boolean) language sql volatile set search_path='' as $$
 select * from public.social_cached_streak(member_id,selected_group,as_of,'work');
$$;
create function public.social_group_habit_streak(member_id uuid,selected_group uuid,as_of timestamptz)
returns table(streak integer,frozen boolean) language sql volatile set search_path='' as $$
 select * from public.social_cached_streak(member_id,selected_group,as_of,'habits');
$$;
revoke all on function public.social_cached_streak(uuid,uuid,timestamptz,text),
 public.social_group_work_streak(uuid,uuid,timestamptz),public.social_group_habit_streak(uuid,uuid,timestamptz)
 from public,anon,authenticated;
