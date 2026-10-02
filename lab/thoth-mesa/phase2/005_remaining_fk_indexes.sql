-- THOTH MESA Phase 2
-- Remaining foreign-key covering indexes identified by Supabase advisor.
-- Non-destructive: indexes only.

create index if not exists idx_budget_limits_thread_id
  on thoth_mesa.budget_limits(thread_id)
  where thread_id is not null;

create index if not exists idx_budget_limits_provider_id
  on thoth_mesa.budget_limits(provider_id)
  where provider_id is not null;

create index if not exists idx_budget_limits_model_id
  on thoth_mesa.budget_limits(model_id)
  where model_id is not null;

create index if not exists idx_provider_health_model_id
  on thoth_mesa.provider_health(model_id)
  where model_id is not null;

create index if not exists idx_routing_decisions_thread_id
  on thoth_mesa.routing_decisions(thread_id)
  where thread_id is not null;

create index if not exists idx_routing_decisions_invocation_id
  on thoth_mesa.routing_decisions(invocation_id)
  where invocation_id is not null;

create index if not exists idx_routing_decisions_selected_provider_id
  on thoth_mesa.routing_decisions(selected_provider_id)
  where selected_provider_id is not null;

create index if not exists idx_routing_decisions_selected_model_id
  on thoth_mesa.routing_decisions(selected_model_id)
  where selected_model_id is not null;
