-- A caller may only tombstone its own consent grants, even if another UUID becomes known.
begin;
create or replace function public.set_research_consent(p_consent_id uuid, p_version text, p_enabled boolean)
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
    if exists (select 1 from public.research_consent_events where user_id = caller and consent_id = p_consent_id and action = 'withdrawn') then
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

commit;
