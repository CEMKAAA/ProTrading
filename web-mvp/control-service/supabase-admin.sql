-- Private authority. No role or catalog configuration is writable through the Data API.
create table if not exists stratum_private.admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  granted_at timestamptz not null default now()
);
create table if not exists stratum_private.strategy_catalog (
  id text primary key check (id ~ '^[a-z0-9_-]{1,100}$'),
  family text not null check (family in ('orb','macross','sol','entrylab')),
  name text not null check (length(name) between 1 and 200),
  symbol text not null,
  source_hash text not null check (source_hash ~ '^[a-f0-9]{64}$'),
  configuration jsonb,
  native_snapshot jsonb not null,
  import_note text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  check (configuration is null or (configuration->>'family'=family and configuration->>'version'='2'))
);
create table if not exists stratum_private.strategy_grants (
  user_id uuid not null references auth.users(id) on delete cascade,
  strategy_id text not null references stratum_private.strategy_catalog(id) on delete cascade,
  enabled boolean not null default false,
  revision bigint not null default 0,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (user_id,strategy_id)
);
create index if not exists strategy_catalog_family_name on stratum_private.strategy_catalog(family,lower(name),id) where active;
create table if not exists stratum_private.strategy_grant_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  user_id uuid not null,
  strategy_id text not null,
  enabled boolean not null,
  revision bigint not null,
  at timestamptz not null default now()
);
alter table stratum_private.admin_roles enable row level security;
alter table stratum_private.strategy_catalog enable row level security;
alter table stratum_private.strategy_grants enable row level security;
alter table stratum_private.strategy_grant_events enable row level security;
revoke all on stratum_private.admin_roles,stratum_private.strategy_catalog,stratum_private.strategy_grants,stratum_private.strategy_grant_events from public,anon,authenticated;

create or replace function stratum_private.admin_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare state jsonb;
begin
  state:=stratum_private.access_state();
  return jsonb_build_object('isAdmin',not (state->>'disabled')::boolean and exists(
    select 1 from stratum_private.admin_roles where user_id=auth.uid() and enabled));
end $$;
create or replace function stratum_private.require_admin() returns uuid
language plpgsql stable security definer set search_path='' as $$
begin
  if not (stratum_private.admin_status()->>'isAdmin')::boolean then
    raise exception 'STRATUM_ADMIN_REQUIRED' using errcode='42501';
  end if;
  return auth.uid();
end $$;
create or replace function stratum_private.admin_users(p_query text default '',p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare items jsonb; total bigint;
begin
  perform stratum_private.require_admin();
  if length(p_query)>200 or p_offset<0 or p_offset>1000000 then raise exception 'STRATUM_INVALID_REQUEST'; end if;
  select count(*) into total from auth.users u where position(lower(p_query) in lower(coalesce(u.email,'')))>0;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into items from (
    select u.id,u.email,coalesce(a.display_name,'') as "displayName",u.created_at as "createdAt",
      u.email_confirmed_at is not null as confirmed,
      coalesce(a.disabled,false) as disabled,
      case when a.disabled then 'inactive' when a.paid_until>now() then 'paid' when t.expires_at>now() then 'demo' else 'inactive' end as "accessMode",
      t.expires_at as "trialUntil",
      (select count(*) from stratum_private.strategy_grants g where g.user_id=u.id and g.enabled) as "grantedCount"
    from auth.users u left join stratum_private.accounts a on a.user_id=u.id
    left join stratum_private.trial_claims t on t.email_hash=a.email_hash
    where position(lower(p_query) in lower(coalesce(u.email,'')))>0
    order by u.created_at desc,u.id limit 50 offset p_offset
  ) q;
  return jsonb_build_object('items',items,'total',total,'hasMore',p_offset+jsonb_array_length(items)<total);
end $$;
create or replace function stratum_private.admin_catalog(p_user_id uuid,p_family text,p_query text default '',p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare items jsonb; total bigint; counts jsonb;
begin
  perform stratum_private.require_admin();
  if p_family not in ('orb','macross','sol','entrylab') or p_offset<0 or p_offset>1000000 or length(p_query)>200 then raise exception 'STRATUM_INVALID_REQUEST'; end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'STRATUM_USER_UNKNOWN'; end if;
  select count(*) into total from stratum_private.strategy_catalog c where c.active and c.family=p_family and position(lower(p_query) in lower(c.name||' '||c.symbol))>0;
  select coalesce(jsonb_object_agg(family,n),'{}') into counts from(select family,count(*) n from stratum_private.strategy_catalog where active group by family) q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into items from (
    select c.id,c.name,c.family,c.symbol,c.configuration is not null as ready,c.import_note as "importNote",
      coalesce(g.enabled,false) as enabled,coalesce(g.revision,0) as revision
    from stratum_private.strategy_catalog c left join stratum_private.strategy_grants g on g.strategy_id=c.id and g.user_id=p_user_id
    where c.active and c.family=p_family and position(lower(p_query) in lower(c.name||' '||c.symbol))>0
    order by lower(c.name),c.id limit 50 offset p_offset
  ) q;
  return jsonb_build_object('items',items,'total',total,'counts',counts,'hasMore',p_offset+jsonb_array_length(items)<total);
end $$;
create or replace function stratum_private.admin_grant(p_user_id uuid,p_strategy_id text,p_enabled boolean,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid; old record; revision bigint;
begin
  actor:=stratum_private.require_admin();
  if p_enabled is null or p_revision is null or p_revision<0 then raise exception 'STRATUM_INVALID_REQUEST'; end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'STRATUM_USER_UNKNOWN'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text||':'||p_strategy_id,0));
  if not exists(select 1 from stratum_private.strategy_catalog where id=p_strategy_id and active and (not p_enabled or configuration is not null)) then
    raise exception 'STRATUM_STRATEGY_NOT_READY';
  end if;
  select * into old from stratum_private.strategy_grants where user_id=p_user_id and strategy_id=p_strategy_id for update;
  revision:=coalesce(old.revision,0);
  if revision<>p_revision then raise exception 'STRATUM_GRANT_CONFLICT' using errcode='40001'; end if;
  if coalesce(old.enabled,false)=p_enabled then return jsonb_build_object('enabled',p_enabled,'revision',revision); end if;
  revision:=revision+1;
  insert into stratum_private.strategy_grants values(p_user_id,p_strategy_id,p_enabled,revision,actor,now())
    on conflict(user_id,strategy_id) do update set enabled=excluded.enabled,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  insert into stratum_private.strategy_grant_events(actor_id,user_id,strategy_id,enabled,revision) values(actor,p_user_id,p_strategy_id,p_enabled,revision);
  return jsonb_build_object('enabled',p_enabled,'revision',revision);
end $$;
create or replace function stratum_private.available_strategies() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare state jsonb; items jsonb;
begin
  state:=stratum_private.access_state();
  if not (state->>'accessActive')::boolean then raise exception 'STRATUM_ACCESS_REQUIRED' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'family',c.family,'symbol',c.symbol,'sourceHash',c.source_hash) order by c.family,lower(c.name),c.id),'[]') into items
    from stratum_private.strategy_catalog c join stratum_private.strategy_grants g on g.strategy_id=c.id
    where c.active and c.configuration is not null and g.user_id=auth.uid() and g.enabled;
  return jsonb_build_object('items',items);
end $$;
create or replace function stratum_private.load_strategy(p_strategy_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare state jsonb; result jsonb;
begin
  state:=stratum_private.access_state();
  if not (state->>'accessActive')::boolean then raise exception 'STRATUM_ACCESS_REQUIRED' using errcode='42501'; end if;
  select jsonb_build_object('id',c.id,'symbol',c.symbol,'sourceHash',c.source_hash,'configuration',c.configuration) into result
    from stratum_private.strategy_catalog c join stratum_private.strategy_grants g on g.strategy_id=c.id
    where c.id=p_strategy_id and c.active and c.configuration is not null and g.user_id=auth.uid() and g.enabled;
  if result is null then raise exception 'STRATUM_STRATEGY_NOT_AVAILABLE' using errcode='42501'; end if;
  return result;
end $$;

-- Thin invoker wrappers expose no definer functions in the public schema.
create or replace function public.stratum_admin_status() returns jsonb language sql stable security invoker set search_path='' as $$ select stratum_private.admin_status(); $$;
create or replace function public.stratum_admin_users(p_query text default '',p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$ select stratum_private.admin_users(p_query,p_offset); $$;
create or replace function public.stratum_admin_catalog(p_user_id uuid,p_family text,p_query text default '',p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$ select stratum_private.admin_catalog(p_user_id,p_family,p_query,p_offset); $$;
create or replace function public.stratum_admin_grant(p_user_id uuid,p_strategy_id text,p_enabled boolean,p_revision bigint) returns jsonb language sql security invoker set search_path='' as $$ select stratum_private.admin_grant(p_user_id,p_strategy_id,p_enabled,p_revision); $$;
create or replace function public.stratum_available_strategies() returns jsonb language sql stable security invoker set search_path='' as $$ select stratum_private.available_strategies(); $$;
create or replace function public.stratum_load_strategy(p_strategy_id text) returns jsonb language sql stable security invoker set search_path='' as $$ select stratum_private.load_strategy(p_strategy_id); $$;
do $$declare fn regprocedure; begin
  for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='stratum_private' and p.proname in ('admin_status','require_admin','admin_users','admin_catalog','admin_grant','available_strategies','load_strategy'))
      or (n.nspname='public' and p.proname in ('stratum_admin_status','stratum_admin_users','stratum_admin_catalog','stratum_admin_grant','stratum_available_strategies','stratum_load_strategy'))
  loop execute format('revoke all on function %s from public,anon',fn); execute format('grant execute on function %s to authenticated',fn); end loop;
end $$;
