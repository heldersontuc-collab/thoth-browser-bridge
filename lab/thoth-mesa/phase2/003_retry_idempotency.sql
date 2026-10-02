-- THOTH MESA Phase 2 retry/idempotency hardening

alter table thoth_mesa.messages
  add column if not exists idempotency_key text;

create unique index if not exists idx_messages_idempotency_key
  on thoth_mesa.messages(idempotency_key)
  where idempotency_key is not null;

alter table thoth_mesa.model_invocations
  add column if not exists idempotency_key text;

create unique index if not exists idx_invocations_idempotency_key
  on thoth_mesa.model_invocations(idempotency_key)
  where idempotency_key is not null;

create or replace function thoth_mesa.append_message_idempotent(
  p_thread_id uuid,
  p_parent_message_id uuid,
  p_invocation_id uuid,
  p_position bigint,
  p_actor_type text,
  p_actor_id text,
  p_content text,
  p_provenance jsonb,
  p_idempotency_key text
)
returns thoth_mesa.messages
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
declare
  v_message thoth_mesa.messages;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  insert into thoth_mesa.messages(
    thread_id,parent_message_id,invocation_id,position,
    actor_type,actor_id,content,provenance,idempotency_key
  )
  values(
    p_thread_id,p_parent_message_id,p_invocation_id,p_position,
    p_actor_type,p_actor_id,p_content,coalesce(p_provenance,'{}'::jsonb),p_idempotency_key
  )
  on conflict (idempotency_key) where idempotency_key is not null
  do nothing
  returning * into v_message;

  if v_message.id is null then
    select * into v_message
    from thoth_mesa.messages
    where idempotency_key=p_idempotency_key;

    if v_message.thread_id is distinct from p_thread_id
       or v_message.position is distinct from p_position
       or v_message.actor_type is distinct from p_actor_type
       or v_message.actor_id is distinct from p_actor_id
       or v_message.content is distinct from p_content then
      raise exception 'IDEMPOTENCY_CONFLICT:message:%', p_idempotency_key;
    end if;
  end if;

  return v_message;
end;
$$;

create or replace function thoth_mesa.begin_invocation_idempotent(
  p_thread_id uuid,
  p_task_id uuid,
  p_provider text,
  p_requested_model text,
  p_route text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns thoth_mesa.model_invocations
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
declare
  v_inv thoth_mesa.model_invocations;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if p_request_sha256 is null or length(p_request_sha256)<>64 then
    raise exception 'REQUEST_SHA256_REQUIRED';
  end if;

  insert into thoth_mesa.model_invocations(
    thread_id,task_id,provider,requested_model,route,status,
    request_sha256,idempotency_key,metadata
  )
  values(
    p_thread_id,p_task_id,p_provider,p_requested_model,p_route,'started',
    p_request_sha256,p_idempotency_key,coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (idempotency_key) where idempotency_key is not null
  do nothing
  returning * into v_inv;

  if v_inv.id is null then
    select * into v_inv
    from thoth_mesa.model_invocations
    where idempotency_key=p_idempotency_key;

    if v_inv.thread_id is distinct from p_thread_id
       or v_inv.task_id is distinct from p_task_id
       or v_inv.provider is distinct from p_provider
       or v_inv.requested_model is distinct from p_requested_model
       or v_inv.request_sha256 is distinct from p_request_sha256 then
      raise exception 'IDEMPOTENCY_CONFLICT:invocation:%', p_idempotency_key;
    end if;
  end if;

  return v_inv;
end;
$$;

do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant execute on function thoth_mesa.append_message_idempotent(
      uuid,uuid,uuid,bigint,text,text,text,jsonb,text
    ) to service_role;

    grant execute on function thoth_mesa.begin_invocation_idempotent(
      uuid,uuid,text,text,text,text,text,jsonb
    ) to service_role;
  end if;
end $$;
