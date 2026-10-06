-- Rollback-only security fixtures, not real users or credentials.
begin;
insert into auth.users(id,email,created_at,email_confirmed_at,raw_user_meta_data)
values ('11111111-1111-4111-8111-111111111111','stratum-rollback-a@example.invalid',now(),now(),'{"paid_until":"2099-01-01","display_name":"Rollback A"}'),
 ('22222222-2222-4222-8222-222222222222','stratum-rollback-b@example.invalid',now(),now(),'{}'),
 ('33333333-3333-4333-8333-333333333333','stratum-rollback-old@example.invalid',now()-interval '31 days',now(),'{}');
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111',now(),now()),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222',now(),now()),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','33333333-3333-4333-8333-333333333333',now(),now());
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if public.stratum_access_state()->>'accessMode' <> 'demo' then raise exception 'DEMO_FAILED'; end if;
  if public.stratum_access_state()->>'paidUntil' <> '0.000000' and (public.stratum_access_state()->>'paidUntil')::numeric <> 0 then raise exception 'METADATA_PRIVILEGE_ESCALATION'; end if;
  if has_table_privilege(current_user,'stratum_private.trial_claims','INSERT') then raise exception 'TRIAL_PRIVILEGE_LEAK'; end if;
  if has_table_privilege(current_user,'stratum_private.accounts','UPDATE') then raise exception 'PAID_PRIVILEGE_LEAK'; end if;
  begin
    insert into public.stratum_strategies(account_id,name,configuration) values
      ('22222222-2222-4222-8222-222222222222','foreign','{"family":"orb"}');
    raise exception 'CROSS_USER_INSERT_ALLOWED';
  exception when insufficient_privilege then null; end;
end $$;
insert into public.stratum_strategies(account_id,name,configuration) values
 ('11111111-1111-4111-8111-111111111111','own','{"family":"orb"}');
update public.stratum_strategies set configuration='{"family":"sol"}' where name='own';
reset role;
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","session_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.stratum_strategies) <> 0 then raise exception 'CROSS_USER_READ_ALLOWED'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if public.stratum_access_state()->>'accessMode' <> 'inactive' then raise exception 'EXPIRED_TRIAL_ACTIVE'; end if;
  begin
    insert into public.stratum_strategies(account_id,name,configuration) values
      ('33333333-3333-4333-8333-333333333333','expired','{"family":"orb"}');
    raise exception 'EXPIRED_TRIAL_CAN_WRITE';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from auth.sessions where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin perform public.stratum_access_state(); raise exception 'REVOKED_SESSION_ACCEPTED';
  exception when invalid_authorization_specification then null; end;
end $$;
reset role;
delete from auth.users where id='33333333-3333-4333-8333-333333333333';
insert into auth.users(id,email,created_at,email_confirmed_at,raw_user_meta_data)
values ('44444444-4444-4444-8444-444444444444','stratum-rollback-old@example.invalid',now(),now(),'{}');
do $$ begin
  if (select t.expires_at>now() from stratum_private.accounts a join stratum_private.trial_claims t using(email_hash)
    where a.user_id='44444444-4444-4444-8444-444444444444') then raise exception 'RE_REGISTER_RESET_TRIAL'; end if;
  if has_function_privilege('anon','public.stratum_access_state()','EXECUTE') then raise exception 'ANON_RPC_LEAK'; end if;
  if has_table_privilege('anon','public.stratum_strategies','SELECT') then raise exception 'ANON_TABLE_LEAK'; end if;
end $$;
select jsonb_build_object('status','PASS','checks',12,'fixtures','rolled_back','project','uvzhrrqzzdjqtmydpvwo');
rollback;
