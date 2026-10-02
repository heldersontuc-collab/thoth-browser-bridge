-- THOTH MESA Phase 2 - machine-to-machine persistence core
-- No UI and no THOTH production integration in this migration.

create extension if not exists pgcrypto;

create schema if not exists thoth_mesa;
revoke all on schema thoth_mesa from public;

create table if not exists thoth_mesa.threads (
  id uuid primary key default gen_random_uuid(),
  mission_key text not null unique,
  subject text not null,
  status text not null default 'open'
    check (status in ('open','paused','closed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists thoth_mesa.model_invocations (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid references thoth_mesa.threads(id) on delete restrict,
  provider text not null,
  requested_model text not null,
  response_model text,
  route text,
  status text not null default 'started'
    check (status in ('started','completed','failed','rate_limited','cancelled')),
  request_sha256 text check (request_sha256 is null or length(request_sha256)=64),
  response_sha256 text check (response_sha256 is null or length(response_sha256)=64),
  prompt_tokens bigint check (prompt_tokens is null or prompt_tokens >= 0),
  completion_tokens bigint check (completion_tokens is null or completion_tokens >= 0),
  estimated_cost_usd numeric(18,8) check (estimated_cost_usd is null or estimated_cost_usd >= 0),
  error_code text,
  metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists thoth_mesa.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references thoth_mesa.threads(id) on delete restrict,
  parent_message_id uuid references thoth_mesa.messages(id) on delete restrict,
  invocation_id uuid references thoth_mesa.model_invocations(id) on delete restrict,
  position bigint not null,
  actor_type text not null check (actor_type in ('ai','system','human')),
  actor_id text not null,
  content text not null,
  content_sha256 text generated always as (encode(digest(content, 'sha256'), 'hex')) stored,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(thread_id, position)
);

create table if not exists thoth_mesa.tasks (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references thoth_mesa.threads(id) on delete restrict,
  kind text not null,
  title text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','claimed','running','blocked','completed','failed','cancelled')),
  priority integer not null default 100,
  idempotency_key text not null unique,
  lease_owner text,
  lease_until timestamptz,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status in ('claimed','running') and lease_owner is not null and lease_until is not null)
    or
    (status not in ('claimed','running'))
  )
);

create table if not exists thoth_mesa.checkpoints (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references thoth_mesa.threads(id) on delete restrict,
  task_id uuid not null references thoth_mesa.tasks(id) on delete restrict,
  version integer not null check (version > 0),
  state jsonb not null,
  state_sha256 text generated always as (encode(digest(state::text, 'sha256'), 'hex')) stored,
  previous_checkpoint_id uuid references thoth_mesa.checkpoints(id) on delete restrict,
  created_by text not null,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  unique(task_id, version)
);

create table if not exists thoth_mesa.decisions (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references thoth_mesa.threads(id) on delete restrict,
  task_id uuid references thoth_mesa.tasks(id) on delete restrict,
  status text not null default 'proposed'
    check (status in ('proposed','accepted','rejected','superseded')),
  statement text not null,
  rationale text,
  evidence_refs jsonb not null default '[]'::jsonb,
  made_by text not null,
  created_at timestamptz not null default now()
);

create table if not exists thoth_mesa.artifacts (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references thoth_mesa.threads(id) on delete restrict,
  task_id uuid references thoth_mesa.tasks(id) on delete restrict,
  kind text not null,
  uri text not null,
  sha256 text not null check (length(sha256)=64),
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(uri, sha256)
);

create table if not exists thoth_mesa.events (
  seq bigint generated always as identity primary key,
  event_id uuid not null default gen_random_uuid() unique,
  thread_id uuid references thoth_mesa.threads(id) on delete restrict,
  entity_type text not null,
  entity_id uuid,
  event_type text not null,
  actor_id text not null,
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  causation_event_id uuid references thoth_mesa.events(event_id) on delete restrict,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_messages_thread_position
  on thoth_mesa.messages(thread_id, position);
create index if not exists idx_tasks_claim
  on thoth_mesa.tasks(priority, created_at)
  where status = 'pending';
create index if not exists idx_tasks_expired_lease
  on thoth_mesa.tasks(lease_until)
  where status in ('claimed','running');
create index if not exists idx_checkpoints_task_version
  on thoth_mesa.checkpoints(task_id, version desc);
create index if not exists idx_events_thread_seq
  on thoth_mesa.events(thread_id, seq);
create index if not exists idx_invocations_thread_started
  on thoth_mesa.model_invocations(thread_id, started_at desc);

create or replace function thoth_mesa.prevent_immutable_mutation()
returns trigger
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
begin
  raise exception 'THOTH_MESA_IMMUTABLE:% cannot be %d', tg_table_name, tg_op;
end;
$$;

drop trigger if exists events_immutable on thoth_mesa.events;
create trigger events_immutable
before update or delete on thoth_mesa.events
for each row execute function thoth_mesa.prevent_immutable_mutation();

drop trigger if exists messages_immutable on thoth_mesa.messages;
create trigger messages_immutable
before update or delete on thoth_mesa.messages
for each row execute function thoth_mesa.prevent_immutable_mutation();

drop trigger if exists checkpoints_immutable on thoth_mesa.checkpoints;
create trigger checkpoints_immutable
before update or delete on thoth_mesa.checkpoints
for each row execute function thoth_mesa.prevent_immutable_mutation();

create or replace function thoth_mesa.append_event(
  p_thread_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_type text,
  p_actor_id text,
  p_payload jsonb,
  p_idempotency_key text,
  p_causation_event_id uuid default null,
  p_correlation_id uuid default null
)
returns thoth_mesa.events
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
declare
  v_event thoth_mesa.events;
begin
  insert into thoth_mesa.events(
    thread_id, entity_type, entity_id, event_type, actor_id,
    payload, idempotency_key, causation_event_id, correlation_id
  )
  values(
    p_thread_id, p_entity_type, p_entity_id, p_event_type, p_actor_id,
    coalesce(p_payload,'{}'::jsonb), p_idempotency_key, p_causation_event_id,
    coalesce(p_correlation_id, gen_random_uuid())
  )
  on conflict (idempotency_key) do nothing
  returning * into v_event;

  if v_event.event_id is null then
    select * into v_event
    from thoth_mesa.events
    where idempotency_key = p_idempotency_key;
  end if;

  return v_event;
end;
$$;

create or replace function thoth_mesa.claim_next_task(
  p_worker_id text,
  p_lease_seconds integer default 60
)
returns setof thoth_mesa.tasks
language sql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
  update thoth_mesa.tasks t
  set status = 'claimed',
      lease_owner = p_worker_id,
      lease_until = now() + make_interval(secs => greatest(p_lease_seconds, 5)),
      attempt_count = t.attempt_count + 1,
      updated_at = now()
  where t.id = (
    select q.id
    from thoth_mesa.tasks q
    where
      q.status = 'pending'
      or (
        q.status in ('claimed','running')
        and q.lease_until < now()
      )
    order by q.priority asc, q.created_at asc
    limit 1
    for update skip locked
  )
  returning t.*;
$$;

create or replace function thoth_mesa.mark_task_running(
  p_task_id uuid,
  p_worker_id text,
  p_lease_seconds integer default 60
)
returns boolean
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
begin
  update thoth_mesa.tasks
  set status='running',
      lease_until=now()+make_interval(secs => greatest(p_lease_seconds,5)),
      updated_at=now()
  where id=p_task_id
    and status='claimed'
    and lease_owner=p_worker_id
    and lease_until >= now();
  return found;
end;
$$;

create or replace function thoth_mesa.complete_task(
  p_task_id uuid,
  p_worker_id text,
  p_result jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
begin
  update thoth_mesa.tasks
  set status='completed',
      result=coalesce(p_result,'{}'::jsonb),
      lease_owner=null,
      lease_until=null,
      updated_at=now()
  where id=p_task_id
    and status in ('claimed','running')
    and lease_owner=p_worker_id
    and lease_until >= now();
  return found;
end;
$$;

-- Supabase backend access only. These blocks are no-ops in vanilla Postgres lab.
do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant usage on schema thoth_mesa to service_role;
    grant select, insert, update on
      thoth_mesa.threads,
      thoth_mesa.model_invocations,
      thoth_mesa.tasks,
      thoth_mesa.decisions
    to service_role;
    grant select, insert on
      thoth_mesa.messages,
      thoth_mesa.checkpoints,
      thoth_mesa.artifacts,
      thoth_mesa.events
    to service_role;
    grant usage, select on all sequences in schema thoth_mesa to service_role;
    grant execute on function thoth_mesa.append_event(uuid,text,uuid,text,text,jsonb,text,uuid,uuid) to service_role;
    grant execute on function thoth_mesa.claim_next_task(text,integer) to service_role;
    grant execute on function thoth_mesa.mark_task_running(uuid,text,integer) to service_role;
    grant execute on function thoth_mesa.complete_task(uuid,text,jsonb) to service_role;
  end if;
end $$;
