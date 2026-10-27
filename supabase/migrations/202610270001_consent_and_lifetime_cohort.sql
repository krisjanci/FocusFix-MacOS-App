-- Apply after 202610250001. No participant collection is enabled by this migration.
begin;

create table public.research_study (
  singleton boolean primary key default true check (singleton),
  version text not null default '',
  recruitment_enabled boolean not null default false,
  collection_enabled boolean not null default false,
  determination_reference text not null default '',
  eligibility_text text not null default 'US residents age 18 or older. Eligibility is verified by the researcher.',
  allegheny_only boolean not null default false,
  researcher_contact text not null default '',
  purpose text not null default '',
  duration text not null default '',
  retention_policy text not null default '',
  risks text not null default '',
  withdrawal_policy text not null default '',
  future_training boolean not null default false,
  information_url text not null default '',
  constraint reviewed_study_required check (
    not (recruitment_enabled or collection_enabled) or
    (length(btrim(version)) > 0 and length(btrim(determination_reference)) > 0
     and length(btrim(researcher_contact)) > 0 and length(btrim(purpose)) > 0
     and length(btrim(duration)) > 0 and length(btrim(retention_policy)) > 0
     and length(btrim(risks)) > 0 and length(btrim(withdrawal_policy)) > 0
     and information_url ~ '^https://[^/[:space:]]+'))
);
insert into public.research_study (singleton) values (true);
alter table public.research_study enable row level security;
revoke all on public.research_study from anon, authenticated;
grant select on public.research_study to authenticated;
create policy study_read on public.research_study for select to authenticated using (true);

-- A monotonic aggregate, not a count of accounts that happen to remain in the database.
alter table public.research_capacity add column selected_count integer not null default 0;
update public.research_capacity set selected_count = (select count(*) from public.research_enrollments);
alter table public.research_capacity add constraint lifetime_cohort_bounded
  check (selected_count between 0 and 50 and max_participants between 1 and 50);
create or replace function public.enforce_research_capacity() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'UPDATE' and new.user_id <> old.user_id then
    raise exception 'Participant identity cannot change';
  end if;
  if TG_OP = 'INSERT' then
    update public.research_capacity set selected_count = selected_count + 1
    where singleton and selected_count < least(max_participants, 50);
    if not found then raise exception 'Research enrollment is full'; end if;
  end if;
  return new;
end;
$$;

alter table public.research_interest
  add column status text not null default 'pending' check (status in ('pending', 'not_selected', 'withdrawn')),
  add column consent_version text not null default '',
  add column adult_us_attested boolean not null default false,
  add column eligible_attested boolean not null default false;
-- Recruitment and eligibility checks cannot be bypassed by a direct table insert.
revoke insert, delete on public.research_interest from authenticated;
drop policy own_interest_insert on public.research_interest;
drop policy own_interest_delete on public.research_interest;

create table public.research_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  consent_id uuid not null unique,
  study_version text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
alter table public.research_consents enable row level security;
revoke all on public.research_consents from anon, authenticated;
grant select on public.research_consents to authenticated;
create policy own_consent_read on public.research_consents for select to authenticated using ((select auth.uid()) = user_id);

-- Preserve consent history while an account exists; no client can modify its audit trail.
create table public.research_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  consent_id uuid not null,
  study_version text not null,
  action text not null check (action in ('granted','withdrawn')),
  occurred_at timestamptz not null default now()
);
alter table public.research_consent_events enable row level security;
revoke all on public.research_consent_events from anon, authenticated;

create table public.research_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  participant_reference uuid not null,
  requested_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','hosted_deleted','completed')),
  completed_at timestamptz
);
create unique index one_open_research_deletion on public.research_deletion_requests (participant_reference) where status <> 'completed';
alter table public.research_deletion_requests enable row level security;
revoke all on public.research_deletion_requests from anon, authenticated;
grant select on public.research_deletion_requests to authenticated;
create policy own_deletion_read on public.research_deletion_requests for select to authenticated using ((select auth.uid()) = user_id);

create function public.request_research_participation(p_version text, p_adult_us boolean, p_eligible boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); study public.research_study;
begin
  select * into study from public.research_study where singleton for share;
  if caller is null or not study.recruitment_enabled or p_version is distinct from study.version
     or p_adult_us is distinct from true or p_eligible is distinct from true then
    raise exception 'Recruitment unavailable or eligibility not confirmed';
  end if;
  if exists (select 1 from public.research_capacity where singleton and selected_count >= least(max_participants,50))
     and not exists (select 1 from public.research_enrollments where user_id = caller) then
    raise exception 'Research enrollment is full';
  end if;
  insert into public.research_interest (user_id, consent_version, adult_us_attested, eligible_attested)
  values (caller, p_version, true, true)
  on conflict (user_id) do nothing;
end;
$$;

create function public.set_research_consent(p_consent_id uuid, p_version text, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); study public.research_study; changed integer;
begin
  if caller is null or p_consent_id is null or p_enabled is null then raise exception 'Authentication and consent required'; end if;
  -- Serialize enable/withdraw/delete per participant; stale withdrawals only revoke their own consent ID.
  perform 1 from auth.users where id = caller for update;
  if p_enabled then
    select * into study from public.research_study where singleton for share;
    if not study.collection_enabled or p_version is distinct from study.version
       or not exists (select 1 from public.research_enrollments where user_id = caller and enabled and consent_version = p_version)
       or not exists (select 1 from public.research_interest where user_id = caller and adult_us_attested and eligible_attested and status = 'pending')
       or exists (select 1 from public.research_deletion_requests where participant_reference = caller and status <> 'completed') then
      raise exception 'Active approval and current study consent required';
    end if;
    -- A withdrawn ID cannot be revived by a delayed request or retry.
    if exists (select 1 from public.research_consent_events where consent_id = p_consent_id and action = 'withdrawn') then
      raise exception 'Consent has been withdrawn';
    end if;
    insert into public.research_consents (user_id, consent_id, study_version)
    values (caller, p_consent_id, p_version)
    on conflict (user_id) do update set consent_id = excluded.consent_id, study_version = excluded.study_version,
      granted_at = now(), withdrawn_at = null;
    insert into public.research_consent_events (user_id, consent_id, study_version, action)
    values (caller, p_consent_id, p_version, 'granted');
  else
    update public.research_consents set withdrawn_at = coalesce(withdrawn_at, now())
    where user_id = caller and consent_id = p_consent_id;
    -- Record even if withdrawal arrived before a delayed grant.
    insert into public.research_consent_events (user_id, consent_id, study_version, action)
    values (caller, p_consent_id, coalesce(p_version,''), 'withdrawn');
  end if;
end;
$$;

create function public.request_research_deletion()
returns uuid language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); request_id uuid; consent public.research_consents;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  perform 1 from auth.users where id = caller for update;
  select * into consent from public.research_consents where user_id = caller;
  if consent.consent_id is not null then
    perform public.set_research_consent(consent.consent_id, consent.study_version, false);
  end if;
  update public.research_interest set status = 'withdrawn' where user_id = caller;
  select id into request_id from public.research_deletion_requests where participant_reference = caller and status <> 'completed';
  if request_id is null then
    insert into public.research_deletion_requests (user_id, participant_reference) values (caller, caller) returning id into request_id;
  end if;
  return request_id;
end;
$$;

-- Exact owner/consent/archive paths; approval alone is insufficient, even via Storage directly.
create function public.can_upload_research(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and array_length(string_to_array(object_name,'/'),1) = 3
    and split_part(object_name,'/',1) = auth.uid()::text
    and split_part(object_name,'/',3) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.zip$'
    and exists (
      select 1 from public.research_consents c
      join public.research_enrollments e on e.user_id = c.user_id
      join public.research_study s on s.singleton
      where c.user_id = auth.uid() and c.withdrawn_at is null
        and c.consent_id::text = split_part(object_name,'/',2)
        and e.enabled and s.collection_enabled
        and c.study_version = s.version and e.consent_version = s.version
    )
    and not exists (select 1 from public.research_deletion_requests where participant_reference = auth.uid() and status <> 'completed');
$$;
drop policy own_research_insert on storage.objects;
drop policy own_research_read on storage.objects;
drop policy own_research_update on storage.objects;
create policy own_research_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'research-sessions' and public.can_upload_research(name));
create policy own_research_read on storage.objects for select to authenticated
  using (bucket_id = 'research-sessions' and public.can_upload_research(name));
create policy own_research_update on storage.objects for update to authenticated
  using (bucket_id = 'research-sessions' and public.can_upload_research(name))
  with check (bucket_id = 'research-sessions' and public.can_upload_research(name));

create or replace function public.confirm_research_upload(p_archive_id uuid, p_object_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_upload_research(p_object_name) then raise exception 'Active consent and research access required'; end if;
  if split_part(p_object_name,'/',3) <> (p_archive_id::text || '.zip') or
     not exists (select 1 from storage.objects where bucket_id = 'research-sessions' and name = p_object_name) then
    raise exception 'Received archive not found';
  end if;
  insert into public.research_upload_receipts (user_id, archive_id, object_name)
  values (auth.uid(), p_archive_id, p_object_name) on conflict (user_id, archive_id) do nothing;
end;
$$;

revoke all on function public.request_research_participation(text,boolean,boolean) from public, anon;
revoke all on function public.set_research_consent(uuid,text,boolean) from public, anon;
revoke all on function public.request_research_deletion() from public, anon;
revoke all on function public.can_upload_research(text) from public, anon;
grant execute on function public.request_research_participation(text,boolean,boolean) to authenticated;
grant execute on function public.set_research_consent(uuid,text,boolean) to authenticated;
grant execute on function public.request_research_deletion() to authenticated;
grant execute on function public.can_upload_research(text) to authenticated;
create function public.research_cohort_full()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select selected_count >= least(max_participants,50) from public.research_capacity where singleton), true);
$$;
revoke all on function public.research_cohort_full() from public, anon;
grant execute on function public.research_cohort_full() to authenticated;
commit;
