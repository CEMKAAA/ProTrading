-- Remote Supabase schema. Auth/trial authority is never writable by a browser.
create schema if not exists stratum_private;
revoke all on schema stratum_private from public, anon, authenticated;
grant usage on schema stratum_private to authenticated;

create table stratum_private.trial_claims (
  email_hash text primary key,
  started_at timestamptz not null,
  expires_at timestamptz not null check (expires_at = started_at + interval '30 days')
);
create table stratum_private.accounts (
  user_id uuid primary key,
  email_hash text not null references stratum_private.trial_claims(email_hash),
  display_name text not null,
  paid_until timestamptz not null default 'epoch',
  disabled boolean not null default false
);
alter table stratum_private.trial_claims enable row level security;
alter table stratum_private.accounts enable row level security;
revoke all on stratum_private.trial_claims, stratum_private.accounts from public, anon, authenticated;

create function stratum_private.on_signup() returns trigger
language plpgsql security definer set search_path = '' as $$
declare fingerprint text; starts timestamptz;
begin
  if new.email is null then return new; end if;
  fingerprint := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.lower(pg_catalog.btrim(new.email)), 'UTF8')), 'hex');
  starts := coalesce(new.created_at, pg_catalog.now());
  insert into stratum_private.trial_claims values (fingerprint, starts, starts + interval '30 days')
    on conflict (email_hash) do nothing;
  insert into stratum_private.accounts(user_id,email_hash,display_name)
    values (new.id,fingerprint,pg_catalog.left(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),pg_catalog.split_part(new.email,'@',1)),60))
    on conflict (user_id) do nothing;
  return new;
end $$;
revoke all on function stratum_private.on_signup() from public, anon, authenticated;
create trigger stratum_signup after insert on auth.users
  for each row execute function stratum_private.on_signup();

create function stratum_private.access_state() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sid uuid; a record; active boolean; mode text;
begin
  sid := nullif(auth.jwt()->>'session_id','')::uuid;
  if uid is null or sid is null or not exists (
    select 1 from auth.sessions s join auth.users u on u.id=s.user_id
    where s.id=sid and s.user_id=uid and u.email_confirmed_at is not null
      and (u.banned_until is null or u.banned_until <= pg_catalog.now())
      and (s.not_after is null or s.not_after > pg_catalog.now())
  ) then raise exception 'STRATUM_SESSION_INVALID' using errcode='28000'; end if;
  select p.*,t.started_at,t.expires_at,u.email into a
    from stratum_private.accounts p
    join stratum_private.trial_claims t using(email_hash)
    join auth.users u on u.id=p.user_id where p.user_id=uid;
  if not found then raise exception 'STRATUM_ACCOUNT_UNKNOWN' using errcode='28000'; end if;
  mode := case when a.disabled then 'inactive' when a.paid_until > pg_catalog.now() then 'paid'
    when a.expires_at > pg_catalog.now() then 'demo' else 'inactive' end;
  active := mode <> 'inactive';
  return pg_catalog.jsonb_build_object('accountId',uid,'sessionId',sid,'email',a.email,
    'displayName',a.display_name,'disabled',a.disabled,'accessActive',active,'accessMode',mode,
    'paidUntil',extract(epoch from a.paid_until)*1000,
    'trial',pg_catalog.jsonb_build_object('startsAt',extract(epoch from a.started_at)*1000,
      'expiresAt',extract(epoch from a.expires_at)*1000),
    'serverNow',extract(epoch from pg_catalog.now())*1000);
end $$;
revoke all on function stratum_private.access_state() from public, anon;
grant execute on function stratum_private.access_state() to authenticated;
create function public.stratum_access_state() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select stratum_private.access_state();
$$;
revoke all on function public.stratum_access_state() from public, anon;
grant execute on function public.stratum_access_state() to authenticated;

create table public.stratum_strategies (
  account_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 70),
  configuration jsonb not null check (jsonb_typeof(configuration)='object'
    and configuration->>'family' in ('orb','macross','sol','entrylab')
    and octet_length(configuration::text) <= 1048576),
  updated_at timestamptz not null default now(),
  primary key(account_id,name)
);
alter table public.stratum_strategies enable row level security;
revoke all on public.stratum_strategies from public, anon;
grant select, insert, update on public.stratum_strategies to authenticated;
create policy own_strategies_read on public.stratum_strategies for select to authenticated
  using (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'accessActive')='true');
create policy own_strategies_insert on public.stratum_strategies for insert to authenticated
  with check (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'accessActive')='true');
create policy own_strategies_update on public.stratum_strategies for update to authenticated
  using (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'accessActive')='true')
  with check (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'accessActive')='true');

comment on table stratum_private.trial_claims is 'Immutable first demo, retained across auth-account deletion. Same canonical email cannot reset demo.';
comment on function public.stratum_access_state() is 'Verified JWT + live auth.sessions check; no client-supplied account ID.';
