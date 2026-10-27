-- Synthetic fixture only. Can also run on a disposable Supabase project after both migrations.
begin;
update public.research_study set version='synthetic-v1', recruitment_enabled=true, collection_enabled=true,
  determination_reference='SYNTHETIC FIXTURE, NOT HUMAN RESEARCH APPROVAL', researcher_contact='test@example.invalid',
  purpose='Synthetic verification', duration='One test', retention_policy='Delete fixtures after test',
  risks='No human data', withdrawal_policy='Revoke access and delete fixtures', information_url='https://example.invalid/study';
insert into auth.users (id,email)
select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'consent-test-'||i||'@example.invalid'
from generate_series(1,51) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.request_research_participation('synthetic-v1',true,true);
reset role;
insert into public.research_enrollments (user_id,enabled,consent_version)
select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,true,'synthetic-v1'
from generate_series(1,50) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ begin
  begin
    insert into storage.objects(bucket_id,name) values('research-sessions',
      '00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.zip');
    raise exception 'Approval without consent allowed' using errcode='P0002';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.research_consents(user_id,consent_id,study_version)
    values(auth.uid(),'10000000-0000-4000-8000-000000000001','synthetic-v1');
    raise exception 'Direct consent write allowed' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select public.set_research_consent('10000000-0000-4000-8000-000000000001','synthetic-v1',true);
insert into storage.objects(bucket_id,name) values('research-sessions',
  '00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.zip');
select public.confirm_research_upload('20000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.zip');
do $$ begin
  if public.can_upload_research('00000000-0000-4000-8000-000000000002/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.zip') then raise exception 'Foreign owner allowed'; end if;
  if public.can_upload_research('00000000-0000-4000-8000-000000000001/wrong/20000000-0000-4000-8000-000000000001.zip') then raise exception 'Wrong consent allowed'; end if;
  if public.can_upload_research('00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/../secret.zip') then raise exception 'Invalid path allowed'; end if;
end $$;
select public.set_research_consent('10000000-0000-4000-8000-000000000001','synthetic-v1',false);
do $$ begin
  if public.can_upload_research('00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001.zip') then raise exception 'Withdrawn consent allowed'; end if;
  begin
    perform public.set_research_consent('10000000-0000-4000-8000-000000000001','synthetic-v1',true);
    raise exception 'Withdrawn ID revived' using errcode='P0002';
  exception when raise_exception then
    if sqlerrm <> 'Consent has been withdrawn' then raise; end if;
  end;
end $$;
select public.set_research_consent('10000000-0000-4000-8000-000000000002','synthetic-v1',true);
-- Late withdrawal must not disable a newer deliberate opt-in.
select public.set_research_consent('10000000-0000-4000-8000-000000000001','synthetic-v1',false);
do $$ begin
  if not public.can_upload_research('00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000001.zip') then raise exception 'Stale withdrawal revoked new consent'; end if;
end $$;
-- Cross-account policy isolation.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
-- Even a known future consent UUID cannot be poisoned for another account.
select public.set_research_consent('10000000-0000-4000-8000-000000000003','synthetic-v1',false);
do $$ begin
  if exists(select 1 from public.research_consents) or exists(select 1 from public.research_upload_receipts) or exists(select 1 from storage.objects) then raise exception 'Cross-user read allowed'; end if;
  begin
    update public.research_enrollments set enabled=true;
    raise exception 'Self approval allowed' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.set_research_consent('10000000-0000-4000-8000-000000000003','synthetic-v1',true);
reset role;
update public.research_study set version='synthetic-v2';
set local role authenticated;
do $$ begin
  if public.can_upload_research('00000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000001.zip') then raise exception 'Stale version allowed'; end if;
end $$;
select public.request_research_deletion();
select public.request_research_deletion();
do $$ begin
  if (select count(*) from public.research_deletion_requests) <> 1 then raise exception 'Deletion request not idempotent'; end if;
end $$;
reset role;
-- Deletion does not reopen a cohort place, and researcher cleanup requests survive it.
delete from auth.users where id in ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000050');
do $$ begin
  if (select selected_count from public.research_capacity where singleton) <> 50 then raise exception 'Lifetime count changed'; end if;
  if not exists(select 1 from public.research_deletion_requests where user_id is null and participant_reference='00000000-0000-4000-8000-000000000001') then raise exception 'Researcher cleanup request lost'; end if;
  begin
    insert into public.research_enrollments(user_id,enabled,consent_version)
    values('00000000-0000-4000-8000-000000000051',true,'synthetic-v2');
    raise exception '51st lifetime participant allowed' using errcode='P0002';
  exception when raise_exception then
    if sqlerrm <> 'Research enrollment is full' then raise; end if;
  end;
  begin
    update public.research_study set retention_policy='';
    raise exception 'Incomplete enabled study allowed' using errcode='P0002';
  exception when check_violation then null; end;
end $$;
rollback;
