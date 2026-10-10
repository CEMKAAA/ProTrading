-- Every change below is rolled back. No production grant is left enabled by a test.
begin;
select set_config('stratum.qa_user',(select a.user_id::text from stratum_private.accounts a
  where not exists(select 1 from stratum_private.admin_roles r where r.user_id=a.user_id and r.enabled)
    and exists(select 1 from auth.sessions s where s.user_id=a.user_id and (s.not_after is null or s.not_after>now())) limit 1),true);
select set_config('stratum.qa_session',(select id::text from auth.sessions where user_id=current_setting('stratum.qa_user')::uuid
  and (not_after is null or not_after>now()) order by created_at desc limit 1),true);
select set_config('stratum.qa_admin',(select a.user_id::text from stratum_private.admin_roles a
  where a.enabled and exists(select 1 from auth.sessions s where s.user_id=a.user_id and (s.not_after is null or s.not_after>now())) limit 1),true);
select set_config('stratum.qa_admin_session',(select id::text from auth.sessions where user_id=current_setting('stratum.qa_admin')::uuid
  and (not_after is null or not_after>now()) order by created_at desc limit 1),true);
select set_config('stratum.qa_strategy',(select id from stratum_private.strategy_catalog where active and configuration is not null
  and campaign_results is not null order by id limit 1),true);
select set_config('stratum.qa_campaign',(select campaign_results::text from stratum_private.strategy_catalog
  where id=current_setting('stratum.qa_strategy')),true);
update stratum_private.strategy_grants set enabled=false where user_id=current_setting('stratum.qa_user')::uuid;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_user'),
  'session_id',current_setting('stratum.qa_session'),'role','authenticated','user_metadata',jsonb_build_object('isAdmin',true))::text,true);
set local role authenticated;
do $$begin
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>0 then raise exception 'QA_DEFAULT_DENY'; end if;
 begin perform campaign_results from stratum_private.strategy_catalog; raise exception 'QA_DIRECT_METRICS_LEAK';
  exception when insufficient_privilege then null; end;
 begin perform public.stratum_admin_catalog(current_setting('stratum.qa_user')::uuid,'orb'); raise exception 'QA_FORGED_ADMIN';
  exception when insufficient_privilege then if sqlerrm<>'STRATUM_ADMIN_REQUIRED' then raise; end if; end;
end $$;
reset role;
insert into stratum_private.strategy_grants(user_id,strategy_id,enabled,updated_by)
  values(current_setting('stratum.qa_user')::uuid,current_setting('stratum.qa_strategy'),true,current_setting('stratum.qa_admin')::uuid)
  on conflict(user_id,strategy_id) do update set enabled=true;
set local role authenticated;
do $$declare items jsonb;begin
 items:=public.stratum_available_strategies()->'items';
 if jsonb_array_length(items)<>1 or items->0->>'id'<>current_setting('stratum.qa_strategy') then raise exception 'QA_GRANT_SCOPE'; end if;
 if items->0->'campaign' is distinct from current_setting('stratum.qa_campaign')::jsonb then raise exception 'QA_CAMPAIGN_VALUES'; end if;
 if jsonb_array_length(items->0->'campaign'->'windows')<>9 then raise exception 'QA_WINDOW_COUNT'; end if;
end $$;
reset role;
-- A changed strategy must not inherit the old campaign's performance.
update stratum_private.strategy_catalog set source_hash=repeat('0',64) where id=current_setting('stratum.qa_strategy');
set local role authenticated;
do $$begin
 if (public.stratum_available_strategies()->'items'->0->'campaign') is distinct from 'null'::jsonb then raise exception 'QA_STALE_RESULTS'; end if;
end $$;
reset role;
update stratum_private.strategy_grants set enabled=false where user_id=current_setting('stratum.qa_user')::uuid;
set local role authenticated;
do $$begin
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>0 then raise exception 'QA_REVOKED_RESULTS'; end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_admin'),
  'session_id',current_setting('stratum.qa_admin_session'),'role','authenticated')::text,true);
do $$declare result jsonb;begin
 if not (public.stratum_admin_status()->>'isAdmin')::boolean then raise exception 'QA_ADMIN'; end if;
 result:=public.stratum_admin_catalog(current_setting('stratum.qa_user')::uuid,'macross');
 if (result->>'total')::int<81 or not (result->'items'->0 ? 'campaign') then raise exception 'QA_ADMIN_CAMPAIGN'; end if;
end $$;
reset role;
select 'PASS' as result,'default deny, direct table denial, forged admin denial, granted exact metrics, stale fingerprint, revoke, admin catalog' as checks;
rollback;
