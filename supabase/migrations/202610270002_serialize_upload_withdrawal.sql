-- Serialize Storage transactions with consent/withdrawal/deletion for the same account.
-- VOLATILE gives the post-lock checks a fresh snapshot after waiting for a withdrawal.
begin;
create or replace function public.can_upload_research(object_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null then return false; end if;
  -- Grants and withdrawal take FOR UPDATE on this same row. Accepted Storage writes
  -- therefore finish before a deletion request can start listing/removing files.
  perform 1 from auth.users where id = caller for share;
  if not found then return false; end if;
  return array_length(string_to_array(object_name,'/'),1) = 3
    and split_part(object_name,'/',1) = caller::text
    and split_part(object_name,'/',3) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.zip$'
    and exists (
      select 1 from public.research_consents c
      join public.research_enrollments e on e.user_id = c.user_id
      join public.research_study s on s.singleton
      where c.user_id = caller and c.withdrawn_at is null
        and c.consent_id::text = split_part(object_name,'/',2)
        and e.enabled and s.collection_enabled
        and c.study_version = s.version and e.consent_version = s.version
    )
    and not exists (select 1 from public.research_deletion_requests where participant_reference = caller and status <> 'completed');
end;
$$;
commit;
