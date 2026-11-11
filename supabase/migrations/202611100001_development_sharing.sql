-- Product-development recordings are separate from the disabled study pipeline.
-- An administrator enables collection and approves each account in the dashboard;
-- the account owner must also grant current, explicit consent in the app.
begin;

create table public.development_collection (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  policy_version text not null default 'development-v1',
  updated_at timestamptz not null default now(),
  constraint development_policy_version_present check (length(btrim(policy_version)) > 0)
);
insert into public.development_collection (singleton) values (true);
alter table public.development_collection enable row level security;
revoke all on public.development_collection from anon, authenticated;
grant select on public.development_collection to authenticated;
create policy development_collection_read on public.development_collection
  for select to authenticated using (true);

create table public.development_approvals (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  max_archives integer not null default 10 check (max_archives between 1 and 100),
  updated_at timestamptz not null default now()
);
alter table public.development_approvals enable row level security;
revoke all on public.development_approvals from anon, authenticated;
grant select on public.development_approvals to authenticated;
create policy own_development_approval_read on public.development_approvals
  for select to authenticated using ((select auth.uid()) = user_id);

create table public.development_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  consent_id uuid not null unique,
  policy_version text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
alter table public.development_consents enable row level security;
revoke all on public.development_consents from anon, authenticated;
grant select on public.development_consents to authenticated;
create policy own_development_consent_read on public.development_consents
  for select to authenticated using ((select auth.uid()) = user_id);

create table public.development_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  consent_id uuid not null,
  policy_version text not null,
  action text not null check (action in ('granted', 'withdrawn')),
  occurred_at timestamptz not null default now()
);
alter table public.development_consent_events enable row level security;
revoke all on public.development_consent_events from anon, authenticated;

create table public.development_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  owner_reference uuid not null,
  requested_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'hosted_deleted', 'completed')),
  completed_at timestamptz
);
create unique index one_open_development_deletion on public.development_deletion_requests (owner_reference)
  where status <> 'completed';
alter table public.development_deletion_requests enable row level security;
revoke all on public.development_deletion_requests from anon, authenticated;
grant select on public.development_deletion_requests to authenticated;
create policy own_development_deletion_read on public.development_deletion_requests
  for select to authenticated using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('development-recordings', 'development-recordings', false, 26214400, array['application/zip']);

create function public.set_development_consent(p_consent_id uuid, p_version text, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); prior public.development_consents; settings public.development_collection;
begin
  if caller is null or p_consent_id is null or p_enabled is null then
    raise exception 'Authentication and consent are required';
  end if;
  -- Serialize consent changes and deletion for this account.
  perform 1 from auth.users where id = caller for update;
  if p_enabled then
    select * into settings from public.development_collection where singleton for share;
    if not settings.enabled or p_version is distinct from settings.policy_version
       or not exists (select 1 from public.development_approvals where user_id = caller and enabled)
       or exists (select 1 from public.development_deletion_requests
                  where owner_reference = caller and status <> 'completed') then
      raise exception 'Development sharing is unavailable for this account';
    end if;
    if exists (select 1 from public.development_consent_events
               where consent_id = p_consent_id and action = 'withdrawn') then
      raise exception 'Withdrawn consent cannot be restored';
    end if;
    select * into prior from public.development_consents where user_id = caller;
    if prior.consent_id is not null and prior.consent_id <> p_consent_id and prior.withdrawn_at is null then
      insert into public.development_consent_events (user_id, consent_id, policy_version, action)
      values (caller, prior.consent_id, prior.policy_version, 'withdrawn');
    end if;
    insert into public.development_consents (user_id, consent_id, policy_version)
    values (caller, p_consent_id, p_version)
    on conflict (user_id) do update set consent_id = excluded.consent_id,
      policy_version = excluded.policy_version, granted_at = now(), withdrawn_at = null;
    insert into public.development_consent_events (user_id, consent_id, policy_version, action)
    values (caller, p_consent_id, p_version, 'granted');
  else
    update public.development_consents set withdrawn_at = coalesce(withdrawn_at, now())
    where user_id = caller and consent_id = p_consent_id;
    -- Also tombstone a withdrawal that reaches the server before a delayed grant.
    insert into public.development_consent_events (user_id, consent_id, policy_version, action)
    values (caller, p_consent_id, coalesce(p_version, ''), 'withdrawn');
  end if;
end;
$$;

create function public.request_development_deletion()
returns uuid language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); request_id uuid; current_consent public.development_consents;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  perform 1 from auth.users where id = caller for update;
  select * into current_consent from public.development_consents where user_id = caller;
  if current_consent.consent_id is not null then
    update public.development_consents set withdrawn_at = coalesce(withdrawn_at, now()) where user_id = caller;
    insert into public.development_consent_events (user_id, consent_id, policy_version, action)
    values (caller, current_consent.consent_id, current_consent.policy_version, 'withdrawn');
  end if;
  select id into request_id from public.development_deletion_requests
  where owner_reference = caller and status <> 'completed';
  if request_id is null then
    insert into public.development_deletion_requests (user_id, owner_reference)
    values (caller, caller) returning id into request_id;
  end if;
  return request_id;
end;
$$;

create function public.can_upload_development(object_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or array_length(string_to_array(object_name, '/'), 1) <> 3
     or split_part(object_name, '/', 1) <> caller::text
     or not (split_part(object_name, '/', 3) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]zip$') then
    return false;
  end if;
  -- Serializes quota checks with uploads and withdrawal for this account.
  perform 1 from auth.users where id = caller for update;
  return exists (
    select 1 from public.development_consents c
    join public.development_approvals a on a.user_id = c.user_id
    join public.development_collection s on s.singleton
    where c.user_id = caller and c.withdrawn_at is null
      and c.consent_id::text = split_part(object_name, '/', 2)
      and c.policy_version = s.policy_version and s.enabled and a.enabled
      and (select count(*) from storage.objects o
           where o.bucket_id = 'development-recordings'
             and o.name like caller::text || '/%') < a.max_archives
  ) and not exists (select 1 from public.development_deletion_requests
                    where owner_reference = caller and status <> 'completed');
end;
$$;
create policy own_development_recording_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'development-recordings' and public.can_upload_development(name));
create policy own_development_recording_read on storage.objects for select to authenticated
  using (bucket_id = 'development-recordings'
    and split_part(name, '/', 1) = (select auth.uid())::text);

revoke all on function public.set_development_consent(uuid, text, boolean) from public, anon;
revoke all on function public.request_development_deletion() from public, anon;
revoke all on function public.can_upload_development(text) from public, anon;
grant execute on function public.set_development_consent(uuid, text, boolean) to authenticated;
grant execute on function public.request_development_deletion() to authenticated;
grant execute on function public.can_upload_development(text) to authenticated;
commit;
