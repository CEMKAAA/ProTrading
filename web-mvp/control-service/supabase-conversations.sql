-- Explicitly saved chats only. No subscription requirement for a user's own data.
create table public.stratum_conversations (
  account_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  title text not null check (length(title) between 1 and 80),
  provider text not null check (provider in ('local','openrouter')),
  locale text not null check (locale in ('en','tr','de')),
  messages jsonb not null check (jsonb_typeof(messages)='array'
    and jsonb_array_length(messages) between 1 and 512
    and octet_length(messages::text)<=1048576),
  message_count integer generated always as (jsonb_array_length(messages)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (account_id,id)
);
create index stratum_conversations_history on public.stratum_conversations(account_id,updated_at desc,id);
-- PostgREST upserts may supply INSERT defaults for an existing row.
create function stratum_private.conversation_timestamps() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_at := case when TG_OP='UPDATE' then old.created_at else now() end;
  new.updated_at := now();
  return new;
end;
$$;
create trigger conversation_timestamps before insert or update on public.stratum_conversations
  for each row execute function stratum_private.conversation_timestamps();
revoke all on function stratum_private.conversation_timestamps() from public,anon,authenticated;
alter table public.stratum_conversations enable row level security;
revoke all on public.stratum_conversations from public,anon;
grant select,insert,update,delete on public.stratum_conversations to authenticated;
create policy own_conversations_read on public.stratum_conversations for select to authenticated
  using (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'disabled')='false');
create policy own_conversations_insert on public.stratum_conversations for insert to authenticated
  with check (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'disabled')='false');
create policy own_conversations_update on public.stratum_conversations for update to authenticated
  using (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'disabled')='false')
  with check (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'disabled')='false');
create policy own_conversations_delete on public.stratum_conversations for delete to authenticated
  using (account_id=(select auth.uid()) and (select stratum_private.access_state()->>'disabled')='false');
comment on table public.stratum_conversations is 'User-initiated chat snapshots. RLS checks owner and live provider session; loading cannot restore tool execution authority.';
