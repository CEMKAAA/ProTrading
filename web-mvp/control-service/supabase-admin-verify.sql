-- Run with the operator connection. All access assertions run as authenticated.
-- Every grant and metadata change is rolled back; no real access is issued by QA.
begin;
select set_config('stratum.qa_admin',(select user_id::text from stratum_private.admin_roles where enabled limit 1),true);
select set_config('stratum.qa_user',(select user_id::text from stratum_private.accounts where user_id not in (select user_id from stratum_private.admin_roles where enabled) limit 1),true);
select set_config('stratum.qa_strategy',(select id from stratum_private.strategy_catalog where configuration is not null order by id limit 1),true);
select set_config('stratum.qa_admin_session',(select id::text from auth.sessions where user_id=current_setting('stratum.qa_admin')::uuid order by created_at desc limit 1),true);
select set_config('stratum.qa_user_session',(select id::text from auth.sessions where user_id=current_setting('stratum.qa_user')::uuid order by created_at desc limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_user'),'session_id',current_setting('stratum.qa_user_session'),'role','authenticated','email','ciracicemberk0@gmail.com','user_metadata',jsonb_build_object('isAdmin',true),'app_metadata',jsonb_build_object('role','admin'))::text,true);
set local role authenticated;
do $$begin
 if (public.stratum_admin_status()->>'isAdmin')::boolean then raise exception 'QA_METADATA_ESCALATION'; end if;
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>0 then raise exception 'QA_DEFAULT_DENY'; end if;
 begin perform public.stratum_admin_users(); raise exception 'QA_USERS_LEAK'; exception when insufficient_privilege then if sqlerrm<>'STRATUM_ADMIN_REQUIRED' then raise; end if; end;
 begin perform public.stratum_admin_catalog(current_setting('stratum.qa_user')::uuid,'orb'); raise exception 'QA_CATALOG_LEAK'; exception when insufficient_privilege then if sqlerrm<>'STRATUM_ADMIN_REQUIRED' then raise; end if; end;
 begin perform public.stratum_load_strategy(current_setting('stratum.qa_strategy')); raise exception 'QA_CONFIGURATION_LEAK'; exception when insufficient_privilege then if sqlerrm<>'STRATUM_STRATEGY_NOT_AVAILABLE' then raise; end if; end;
 begin update stratum_private.admin_roles set enabled=true; raise exception 'QA_ROLE_WRITE'; exception when insufficient_privilege then null; end;
 begin insert into stratum_private.strategy_grants(user_id,strategy_id,enabled,updated_by) values(current_setting('stratum.qa_user')::uuid,current_setting('stratum.qa_strategy'),true,current_setting('stratum.qa_user')::uuid); raise exception 'QA_GRANT_WRITE'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_admin'),'session_id',current_setting('stratum.qa_admin_session'),'role','authenticated')::text,true);
do $$declare result jsonb; begin
 if not (public.stratum_admin_status()->>'isAdmin')::boolean then raise exception 'QA_ADMIN_MISSING'; end if;
 if (public.stratum_admin_users()->>'total')::int<2 then raise exception 'QA_USER_LIST'; end if;
 if (public.stratum_admin_catalog(current_setting('stratum.qa_user')::uuid,'macross')->>'total')::int<>81 then raise exception 'QA_CATALOG_COUNT'; end if;
 result:=public.stratum_admin_grant(current_setting('stratum.qa_user')::uuid,current_setting('stratum.qa_strategy'),true,0);
 if result<>jsonb_build_object('enabled',true,'revision',1) then raise exception 'QA_GRANT_ON'; end if;
 begin perform public.stratum_admin_grant(current_setting('stratum.qa_user')::uuid,current_setting('stratum.qa_strategy'),false,0); raise exception 'QA_STALE_WRITE'; exception when serialization_failure then if sqlerrm<>'STRATUM_GRANT_CONFLICT' then raise; end if; end;
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>0 then raise exception 'QA_CROSS_USER'; end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_user'),'session_id',current_setting('stratum.qa_user_session'),'role','authenticated')::text,true);
do $$begin
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>1 then raise exception 'QA_GRANT_VISIBILITY'; end if;
 if public.stratum_load_strategy(current_setting('stratum.qa_strategy'))->'configuration'->>'family' is null then raise exception 'QA_GRANT_LOAD'; end if;
 begin perform public.stratum_admin_grant(current_setting('stratum.qa_admin')::uuid,current_setting('stratum.qa_strategy'),true,0); raise exception 'QA_USER_GRANTS_SELF'; exception when insufficient_privilege then if sqlerrm<>'STRATUM_ADMIN_REQUIRED' then raise; end if; end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_admin'),'session_id',current_setting('stratum.qa_admin_session'),'role','authenticated')::text,true);
do $$begin
 if public.stratum_admin_grant(current_setting('stratum.qa_user')::uuid,current_setting('stratum.qa_strategy'),false,1)<>jsonb_build_object('enabled',false,'revision',2) then raise exception 'QA_GRANT_OFF'; end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_user'),'session_id',current_setting('stratum.qa_user_session'),'role','authenticated')::text,true);
do $$begin
 if jsonb_array_length(public.stratum_available_strategies()->'items')<>0 then raise exception 'QA_REVOKED_VISIBLE'; end if;
 begin perform public.stratum_load_strategy(current_setting('stratum.qa_strategy')); raise exception 'QA_REVOKED_LOAD'; exception when insufficient_privilege then if sqlerrm<>'STRATUM_STRATEGY_NOT_AVAILABLE' then raise; end if; end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('stratum.qa_admin'),'session_id','00000000-0000-4000-8000-000000000000','role','authenticated')::text,true);
do $$begin
 begin perform public.stratum_admin_status(); raise exception 'QA_SESSION_BYPASS'; exception when invalid_authorization_specification then if sqlerrm<>'STRATUM_SESSION_INVALID' then raise; end if; end;
end $$;
select 'PASS' as status,'default deny, forged metadata, private table writes, admin user/catalog list, grant on/load/off, cross-user isolation, stale revision, invalid session' as checks;
rollback;
