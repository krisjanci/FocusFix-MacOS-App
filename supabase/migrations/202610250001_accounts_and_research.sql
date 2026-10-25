-- Deploy to a project in a FREE organization only. This does not change billing plans.
-- Stage 1 profiles are private; no public leaderboard or activity totals are exposed.
create table public.account_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  profile jsonb not null,
  constraint bounded_profile check (
    jsonb_typeof(profile) = 'object' and
    profile ?& array['name','symbol','color'] and
    (profile - array['name','symbol','color','photo']) = '{}'::jsonb and
    jsonb_typeof(profile->'name') = 'string' and
    jsonb_typeof(profile->'symbol') = 'string' and
    jsonb_typeof(profile->'color') = 'string' and
    char_length(btrim(profile->>'name')) between 1 and 40 and
    profile->>'symbol' in ('person.fill','leaf.fill','sun.max.fill','moon.stars.fill','bolt.fill','book.fill') and
    profile->>'color' in ('teal','blue','purple','orange','pink') and
    octet_length(profile::text) <= 1500000
  )
);
alter table public.account_profiles enable row level security;
revoke all on public.account_profiles from anon;
grant select, insert, update, delete on public.account_profiles to authenticated;
create policy own_profile_read on public.account_profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy own_profile_insert on public.account_profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy own_profile_update on public.account_profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_profile_delete on public.account_profiles for delete to authenticated using ((select auth.uid()) = user_id);

-- Researcher-managed enrollment. Accounts never approve themselves.
create table public.research_capacity (
  singleton boolean primary key default true check (singleton),
  max_participants integer not null default 50 check (max_participants between 1 and 100)
);
insert into public.research_capacity (singleton, max_participants) values (true, 50);
alter table public.research_capacity enable row level security;
revoke all on public.research_capacity from anon, authenticated;

create table public.research_interest (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now()
);
alter table public.research_interest enable row level security;
revoke all on public.research_interest from anon;
grant select, insert, delete on public.research_interest to authenticated;
create policy own_interest_read on public.research_interest for select to authenticated using ((select auth.uid()) = user_id);
create policy own_interest_insert on public.research_interest for insert to authenticated with check ((select auth.uid()) = user_id);
create policy own_interest_delete on public.research_interest for delete to authenticated using ((select auth.uid()) = user_id);

create table public.research_enrollments (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  consent_version text not null check (char_length(btrim(consent_version)) > 0),
  approved_at timestamptz not null default now()
);
alter table public.research_enrollments enable row level security;
revoke all on public.research_enrollments from anon, authenticated;
grant select on public.research_enrollments to authenticated;
create policy own_enrollment_read on public.research_enrollments for select to authenticated using ((select auth.uid()) = user_id);

-- The locked singleton serializes simultaneous cohort additions, enforcing the cap server-side.
create function public.enforce_research_capacity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare maximum integer;
begin
  if TG_OP = 'INSERT' then
    select max_participants into maximum from public.research_capacity where singleton = true for update;
    if maximum is null or (select count(*) from public.research_enrollments where user_id <> new.user_id) >= maximum then
      raise exception 'Research enrollment is full';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_research_capacity() from public, anon, authenticated;
create trigger enforce_research_capacity before insert or update on public.research_enrollments
for each row execute function public.enforce_research_capacity();

-- Private ZIPs are downloaded by the project owner from the dashboard.
-- Upserts reuse the same batch path after a retry; no public or cross-user reads.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('research-sessions', 'research-sessions', false, 26214400, array['application/zip']);
create policy own_research_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'research-sessions' and (storage.foldername(name))[1] = (select auth.uid()::text) and exists (select 1 from public.research_enrollments e where e.user_id = (select auth.uid()) and e.enabled));
create policy own_research_read on storage.objects for select to authenticated
  using (bucket_id = 'research-sessions' and (storage.foldername(name))[1] = (select auth.uid()::text) and exists (select 1 from public.research_enrollments e where e.user_id = (select auth.uid()) and e.enabled));
create policy own_research_update on storage.objects for update to authenticated
  using (bucket_id = 'research-sessions' and (storage.foldername(name))[1] = (select auth.uid()::text) and exists (select 1 from public.research_enrollments e where e.user_id = (select auth.uid()) and e.enabled))
  with check (bucket_id = 'research-sessions' and (storage.foldername(name))[1] = (select auth.uid()::text) and exists (select 1 from public.research_enrollments e where e.user_id = (select auth.uid()) and e.enabled));

-- Durable receipts survive nightly object cleanup and prevent retry re-uploads.
create table public.research_upload_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  archive_id uuid not null,
  object_name text not null,
  received_at timestamptz not null default now(),
  primary key (user_id, archive_id)
);
alter table public.research_upload_receipts enable row level security;
revoke all on public.research_upload_receipts from anon, authenticated;
grant select on public.research_upload_receipts to authenticated;
create policy own_receipt_read on public.research_upload_receipts for select to authenticated
using ((select auth.uid()) = user_id);
create function public.confirm_research_upload(p_archive_id uuid, p_object_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or not exists (select 1 from public.research_enrollments where user_id = caller and enabled) then
    raise exception 'Research access required';
  end if;
  if split_part(p_object_name, '/', 1) <> caller::text or
     split_part(p_object_name, '/', 3) <> (p_archive_id::text || '.zip') or
     array_length(string_to_array(p_object_name, '/'), 1) <> 3 or
     not exists (select 1 from storage.objects where bucket_id = 'research-sessions' and name = p_object_name) then
    raise exception 'Received archive not found';
  end if;
  insert into public.research_upload_receipts (user_id, archive_id, object_name)
  values (caller, p_archive_id, p_object_name)
  on conflict (user_id, archive_id) do nothing;
end;
$$;
revoke all on function public.confirm_research_upload(uuid, text) from public, anon;
grant execute on function public.confirm_research_upload(uuid, text) to authenticated;
