begin;
-- Own-profile checks return a fingerprint instead of repeatedly transferring images.
-- The authenticated identity is the only row selector; no user id is accepted.
create function public.account_profile_state(p_version text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare value jsonb; version text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select profile into value from public.account_profiles where user_id=auth.uid();
 if value is null then
  return jsonb_build_object('version',null,'unchanged',false,'profile',null);
 end if;
 version:=md5(value::text);
 if version=p_version then
  return jsonb_build_object('version',version,'unchanged',true);
 end if;
 return jsonb_build_object('version',version,'unchanged',false,'profile',value);
end;
$$;
revoke all on function public.account_profile_state(text) from public,anon;
grant execute on function public.account_profile_state(text) to authenticated;
commit;
