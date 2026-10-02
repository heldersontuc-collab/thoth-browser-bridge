-- THOTH MESA Phase 2 router core
-- Adds explicit provider health, budget limits and auditable routing decisions.

alter table thoth_mesa.model_invocations
  add column if not exists task_id uuid references thoth_mesa.tasks(id) on delete restrict;

create index if not exists idx_invocations_task_started
  on thoth_mesa.model_invocations(task_id, started_at desc)
  where task_id is not null;

create table if not exists thoth_mesa.providers (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null unique,
  display_name text not null,
  enabled boolean not null default true,
  priority integer not null default 100,
  transport text not null check (transport in ('api','gateway','browser','local')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists thoth_mesa.models (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references thoth_mesa.providers(id) on delete restrict,
  model_key text not null,
  family text not null,
  capabilities jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  quality_tier integer,
  cost_class text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(provider_id, model_key)
);

create table if not exists thoth_mesa.provider_health (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references thoth_mesa.providers(id) on delete restrict,
  model_id uuid references thoth_mesa.models(id) on delete restrict,
  state text not null check (
    state in ('healthy','degraded','rate_limited','quota_exhausted','unavailable','auth_required','unknown')
  ),
  observed_at timestamptz not null default now(),
  retry_after timestamptz,
  source text not null,
  detail jsonb not null default '{}'::jsonb
);

create table if not exists thoth_mesa.budget_limits (
  id uuid primary key default gen_random_uuid(),
  scope_type text not null check (scope_type in ('global','thread','task','provider','model')),
  thread_id uuid references thoth_mesa.threads(id) on delete restrict,
  task_id uuid references thoth_mesa.tasks(id) on delete restrict,
  provider_id uuid references thoth_mesa.providers(id) on delete restrict,
  model_id uuid references thoth_mesa.models(id) on delete restrict,
  max_cost_usd numeric(18,8) not null check (max_cost_usd >= 0),
  enabled boolean not null default true,
  window_start timestamptz,
  window_end timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (
    (scope_type='global' and thread_id is null and task_id is null and provider_id is null and model_id is null)
    or
    (scope_type='thread' and thread_id is not null and task_id is null and provider_id is null and model_id is null)
    or
    (scope_type='task' and task_id is not null and provider_id is null and model_id is null)
    or
    (scope_type='provider' and provider_id is not null and model_id is null)
    or
    (scope_type='model' and model_id is not null)
  )
);

create table if not exists thoth_mesa.routing_decisions (
  id uuid primary key default gen_random_uuid(),
  decision_key text not null unique,
  thread_id uuid references thoth_mesa.threads(id) on delete restrict,
  task_id uuid references thoth_mesa.tasks(id) on delete restrict,
  requested_family text,
  selected_provider_id uuid references thoth_mesa.providers(id) on delete restrict,
  selected_model_id uuid references thoth_mesa.models(id) on delete restrict,
  outcome text not null check (
    outcome in ('selected','blocked_no_healthy_model','blocked_budget_exhausted')
  ),
  reason text not null,
  fallback_index integer not null default 0 check (fallback_index >= 0),
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_models_provider_enabled
  on thoth_mesa.models(provider_id, enabled);

create index if not exists idx_provider_health_lookup
  on thoth_mesa.provider_health(provider_id, model_id, observed_at desc);

create index if not exists idx_budget_limits_task
  on thoth_mesa.budget_limits(task_id)
  where enabled and scope_type='task';

create index if not exists idx_routing_task_created
  on thoth_mesa.routing_decisions(task_id, created_at desc)
  where task_id is not null;

alter table thoth_mesa.providers enable row level security;
alter table thoth_mesa.models enable row level security;
alter table thoth_mesa.provider_health enable row level security;
alter table thoth_mesa.budget_limits enable row level security;
alter table thoth_mesa.routing_decisions enable row level security;

create or replace function thoth_mesa.route_next_model(
  p_thread_id uuid,
  p_task_id uuid,
  p_requested_family text,
  p_decision_key text
)
returns thoth_mesa.routing_decisions
language plpgsql
security invoker
set search_path = thoth_mesa, pg_temp
as $$
declare
  v_existing thoth_mesa.routing_decisions;
  v_decision thoth_mesa.routing_decisions;
  v_spent numeric(18,8);
  v_budget numeric(18,8);
  v_provider_id uuid;
  v_model_id uuid;
  v_provider_key text;
  v_model_key text;
  v_health_state text;
  v_retry_after timestamptz;
begin
  select * into v_existing
  from thoth_mesa.routing_decisions
  where decision_key = p_decision_key;

  if v_existing.id is not null then
    return v_existing;
  end if;

  select coalesce(sum(estimated_cost_usd),0)
  into v_spent
  from thoth_mesa.model_invocations
  where task_id = p_task_id
    and status in ('started','completed','rate_limited','failed');

  select min(max_cost_usd)
  into v_budget
  from thoth_mesa.budget_limits
  where enabled
    and scope_type='task'
    and task_id=p_task_id
    and (window_start is null or window_start <= now())
    and (window_end is null or window_end > now());

  if v_budget is not null and v_spent >= v_budget then
    insert into thoth_mesa.routing_decisions(
      decision_key,thread_id,task_id,requested_family,
      outcome,reason,fallback_index,snapshot
    )
    values(
      p_decision_key,p_thread_id,p_task_id,p_requested_family,
      'blocked_budget_exhausted','task budget exhausted',0,
      jsonb_build_object('spent_usd',v_spent,'budget_usd',v_budget)
    )
    returning * into v_decision;

    return v_decision;
  end if;

  with candidates as (
    select
      p.id as provider_id,
      m.id as model_id,
      p.provider_key,
      m.model_key,
      p.priority,
      coalesce(m.quality_tier,0) as quality_tier,
      h.state as health_state,
      h.retry_after,
      row_number() over (
        order by p.priority asc, coalesce(m.quality_tier,0) desc, m.model_key asc
      ) - 1 as fallback_index
    from thoth_mesa.providers p
    join thoth_mesa.models m
      on m.provider_id=p.id
    left join lateral (
      select ph.state, ph.retry_after
      from thoth_mesa.provider_health ph
      where ph.provider_id=p.id
        and (ph.model_id=m.id or ph.model_id is null)
      order by
        case when ph.model_id=m.id then 0 else 1 end,
        ph.observed_at desc
      limit 1
    ) h on true
    where p.enabled
      and m.enabled
      and (p_requested_family is null or m.family=p_requested_family)
      and (
        h.state is null
        or h.state in ('healthy','degraded','unknown')
        or (
          h.state in ('rate_limited','quota_exhausted','unavailable','auth_required')
          and h.retry_after is not null
          and h.retry_after <= now()
        )
      )
  )
  select provider_id,model_id,provider_key,model_key,health_state,retry_after
  into v_provider_id,v_model_id,v_provider_key,v_model_key,v_health_state,v_retry_after
  from candidates
  order by fallback_index
  limit 1;

  if v_model_id is null then
    insert into thoth_mesa.routing_decisions(
      decision_key,thread_id,task_id,requested_family,
      outcome,reason,fallback_index,snapshot
    )
    values(
      p_decision_key,p_thread_id,p_task_id,p_requested_family,
      'blocked_no_healthy_model','no eligible healthy model',0,
      jsonb_build_object('spent_usd',v_spent,'budget_usd',v_budget)
    )
    returning * into v_decision;

    return v_decision;
  end if;

  insert into thoth_mesa.routing_decisions(
    decision_key,thread_id,task_id,requested_family,
    selected_provider_id,selected_model_id,outcome,reason,fallback_index,snapshot
  )
  select
    p_decision_key,p_thread_id,p_task_id,p_requested_family,
    c.provider_id,c.model_id,'selected',
    'selected healthiest eligible model within budget',
    c.fallback_index,
    jsonb_build_object(
      'provider_key',c.provider_key,
      'model_key',c.model_key,
      'health_state',coalesce(c.health_state,'unobserved'),
      'retry_after',c.retry_after,
      'spent_usd',v_spent,
      'budget_usd',v_budget
    )
  from (
    select
      p.id as provider_id,
      m.id as model_id,
      p.provider_key,
      m.model_key,
      h.state as health_state,
      h.retry_after,
      row_number() over (
        order by p.priority asc, coalesce(m.quality_tier,0) desc, m.model_key asc
      ) - 1 as fallback_index
    from thoth_mesa.providers p
    join thoth_mesa.models m on m.provider_id=p.id
    left join lateral (
      select ph.state, ph.retry_after
      from thoth_mesa.provider_health ph
      where ph.provider_id=p.id
        and (ph.model_id=m.id or ph.model_id is null)
      order by
        case when ph.model_id=m.id then 0 else 1 end,
        ph.observed_at desc
      limit 1
    ) h on true
    where p.id=v_provider_id and m.id=v_model_id
  ) c
  returning * into v_decision;

  return v_decision;
end;
$$;

do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant select, insert, update on
      thoth_mesa.providers,
      thoth_mesa.models,
      thoth_mesa.provider_health,
      thoth_mesa.budget_limits
    to service_role;

    grant select, insert on thoth_mesa.routing_decisions to service_role;
    grant execute on function thoth_mesa.route_next_model(uuid,uuid,text,text) to service_role;
  end if;
end $$;
