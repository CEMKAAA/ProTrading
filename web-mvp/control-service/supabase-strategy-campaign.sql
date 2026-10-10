-- Add verified campaign results without changing settings or strategy grants.
alter table stratum_private.strategy_catalog add column if not exists campaign_results jsonb;

create or replace function stratum_private.available_strategies() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare state jsonb; items jsonb;
begin
  state:=stratum_private.access_state();
  if not (state->>'accessActive')::boolean then raise exception 'STRATUM_ACCESS_REQUIRED' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'family',c.family,'symbol',c.symbol,'sourceHash',c.source_hash,
    'campaign',case when c.campaign_results->>'strategySourceHash'=c.source_hash then c.campaign_results else null end) order by c.family,lower(c.name),c.id),'[]') into items
    from stratum_private.strategy_catalog c join stratum_private.strategy_grants g on g.strategy_id=c.id
    where c.active and c.configuration is not null and g.user_id=auth.uid() and g.enabled;
  return jsonb_build_object('items',items);
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
      coalesce(g.enabled,false) as enabled,coalesce(g.revision,0) as revision,
      case when c.campaign_results->>'strategySourceHash'=c.source_hash then c.campaign_results else null end as campaign
    from stratum_private.strategy_catalog c left join stratum_private.strategy_grants g on g.strategy_id=c.id and g.user_id=p_user_id
    where c.active and c.family=p_family and position(lower(p_query) in lower(c.name||' '||c.symbol))>0
    order by lower(c.name),c.id limit 50 offset p_offset
  ) q;
  return jsonb_build_object('items',items,'total',total,'counts',counts,'hasMore',p_offset+jsonb_array_length(items)<total);
end $$;

-- CREATE OR REPLACE retains existing execution grants; private tables remain inaccessible.
revoke all on stratum_private.strategy_catalog from public,anon,authenticated;
alter table stratum_private.strategy_catalog enable row level security;
