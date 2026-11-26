-- Accounts already have a validated, fixed scoring timezone. Avoid enumerating the
-- timezone catalog on every poll; still validate every new or different input.
create function public.social_valid_timezone(selected_zone text) returns boolean
language sql stable set search_path='' as $$
 select case when exists(select 1 from public.social_accounts where user_id=auth.uid() and timezone=selected_zone)
 then true else exists(select 1 from pg_timezone_names where name=selected_zone) end;
$$;
revoke all on function public.social_valid_timezone(text) from public,anon,authenticated;
do $migration$
declare name text; definition text;
 old_guard text:='not exists(select 1 from pg_timezone_names where name=zone)';
begin
 foreach name in array array['social_state_daily_points','social_state'] loop
  definition:=pg_get_functiondef(format('public.%I(text,jsonb)',name)::regprocedure);
  if position(old_guard in definition)=0 then raise exception 'Unexpected timezone guard in %',name; end if;
  execute replace(definition,old_guard,'not public.social_valid_timezone(zone)');
 end loop;
end;
$migration$;

-- Freeze history grows with account age. Send unchanged scoring metadata once,
-- rather than retransmitting every historical freeze on every work checkpoint.
create function public.social_compact_progress_metadata(state jsonb,payload jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare metadata jsonb:=(state->'progress')-'days'; version text; included boolean;
begin
 version:=md5(metadata::text);
 included:=not(payload ? 'progressRevision') or version is distinct from payload->>'progressMetadataVersion';
 if not included then
  state:=jsonb_set(state,'{progress}',jsonb_build_object('version',state->'progress'->'version','days',state->'progress'->'days'));
 end if;
 return state || jsonb_build_object('progressMetadataVersion',version,'progressMetadataIncluded',included);
end;
$$;
revoke all on function public.social_compact_progress_metadata(jsonb,jsonb) from public,anon,authenticated;
do $migration$
declare definition text:=pg_get_functiondef('public.social_state(text,jsonb)'::regprocedure);
 marker text:=$old$return state || jsonb_build_object('groups',response_groups$old$;
begin
 if position(marker in definition)=0 then raise exception 'Unexpected compact response; review metadata migration'; end if;
 execute replace(definition,marker,$new$return public.social_compact_progress_metadata(state,p_payload) || jsonb_build_object('groups',response_groups$new$);
end;
$migration$;
