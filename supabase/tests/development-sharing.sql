-- Isolated product-development sharing checks. All identities are synthetic.
begin;
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'development-one@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'development-two@example.invalid');
insert into public.development_approvals (user_id, enabled) values
  ('11111111-1111-4111-8111-111111111111', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
do $$ begin
  begin
    insert into public.development_approvals(user_id, enabled)
    values (auth.uid(), true);
    raise exception 'User approved themselves';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_development_consent('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'development-v1', true);
    raise exception 'Disabled collection granted consent';
  exception when raise_exception then
    if sqlerrm <> 'Development sharing is unavailable for this account' then raise; end if;
  end;
end $$;
reset role;
update public.development_collection set enabled = true;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
do $$ begin
  if public.can_upload_development('11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip')
  then raise exception 'Approval without consent allowed upload'; end if;
end $$;
select public.set_development_consent('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'development-v1', true);
do $$ begin
  if not public.can_upload_development('11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip')
  then raise exception 'Approved consent could not upload'; end if;
  if public.can_upload_development('22222222-2222-4222-8222-222222222222/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip')
  then raise exception 'Foreign owner allowed'; end if;
end $$;
insert into storage.objects(bucket_id, name) values ('development-recordings',
  '11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip');
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
do $$ begin
  if exists (select 1 from public.development_approvals)
     or exists (select 1 from public.development_consents)
     or exists (select 1 from storage.objects where bucket_id = 'development-recordings')
  then raise exception 'Other account data visible'; end if;
  begin
    perform public.set_development_consent('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'development-v1', true);
    raise exception 'Unapproved account granted consent';
  exception when raise_exception then
    if sqlerrm <> 'Development sharing is unavailable for this account' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select public.set_development_consent('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'development-v1', false);
do $$ begin
  if public.can_upload_development('11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip')
  then raise exception 'Withdrawn consent still uploads'; end if;
  begin
    perform public.set_development_consent('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'development-v1', true);
    raise exception 'Withdrawn consent was revived';
  exception when raise_exception then
    if sqlerrm <> 'Withdrawn consent cannot be restored' then raise; end if;
  end;
end $$;
select public.set_development_consent('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'development-v1', true);
select public.request_development_deletion();
select public.request_development_deletion();
do $$ begin
  if (select count(*) from public.development_deletion_requests) <> 1
  then raise exception 'Deletion request was duplicated'; end if;
  if public.can_upload_development('11111111-1111-4111-8111-111111111111/dddddddd-dddd-4ddd-8ddd-dddddddddddd/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.zip')
  then raise exception 'Deletion did not stop uploads'; end if;
end $$;
rollback;
