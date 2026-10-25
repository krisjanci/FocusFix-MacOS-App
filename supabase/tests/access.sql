-- Run ONLY on a disposable development project after the migration. Everything rolls back.
-- This tests SQL policies/capacity, not Storage's HTTP file-size enforcement.
begin;
insert into auth.users (id, email)
select ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
       'synthetic-' || i || '@example.invalid'
from generate_series(1, 51) i;
insert into public.account_profiles (user_id, profile)
select id, '{"name":"Synthetic","symbol":"leaf.fill","color":"teal"}'::jsonb
from auth.users where email like 'synthetic-%@example.invalid';
insert into public.research_enrollments (user_id, enabled, consent_version)
select ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid, true, 'synthetic-consent'
from generate_series(1, 50) i;
do $$ begin
  begin
    insert into public.research_enrollments (user_id, enabled, consent_version)
    values ('00000000-0000-4000-8000-000000000051', true, 'synthetic-consent');
    raise exception 'The 51st approval unexpectedly succeeded' using errcode = 'P0002';
  exception when raise_exception then
    if sqlerrm <> 'Research enrollment is full' then raise; end if;
  end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$ declare changed integer; begin
  if (select count(*) from public.account_profiles) <> 1 then raise exception 'Cross-user profile read'; end if;
  update public.account_profiles set profile = '{"name":"Changed","symbol":"leaf.fill","color":"teal"}'::jsonb
  where user_id = '00000000-0000-4000-8000-000000000002';
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Cross-user profile update'; end if;
  begin
    update public.research_enrollments set enabled = true;
    raise exception 'Client can approve itself' using errcode = 'P0002';
  exception when insufficient_privilege then null; end;
  begin
    update public.research_capacity set max_participants = 100;
    raise exception 'Client can raise enrollment cap' using errcode = 'P0002';
  exception when insufficient_privilege then null; end;
  insert into storage.objects (bucket_id, name)
  values ('research-sessions', '00000000-0000-4000-8000-000000000001/consent/synthetic.zip');
  begin
    perform public.confirm_research_upload('00000000-0000-4000-8000-000000000099',
        '00000000-0000-4000-8000-000000000001/consent/missing.zip');
    raise exception 'Forged receipt allowed' using errcode = 'P0002';
  exception when raise_exception then
    if sqlerrm <> 'Received archive not found' then raise; end if;
  end;
  begin
    insert into storage.objects (bucket_id, name)
    values ('research-sessions', '00000000-0000-4000-8000-000000000002/consent/foreign.zip');
    raise exception 'Cross-user upload allowed' using errcode = 'P0002';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.research_enrollments set enabled = false where user_id = '00000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$ begin
  begin
    insert into storage.objects (bucket_id, name)
    values ('research-sessions', '00000000-0000-4000-8000-000000000001/consent/revoked.zip');
    raise exception 'Revoked participant can upload' using errcode = 'P0002';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
