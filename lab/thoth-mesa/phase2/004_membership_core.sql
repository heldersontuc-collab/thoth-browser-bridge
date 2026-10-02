-- THOTH MESA Phase 2 membership/governance core

create table if not exists thoth_mesa.members (
  id uuid primary key default gen_random_uuid(),
  member_key text not null unique,
  model_id uuid references thoth_mesa.models(id) on delete restrict,
  member_type text not null check (member_type in ('model','coordinator')),
  logical_role text not null,
  participation_status text not null
    check (participation_status in ('verified','candidate','retired')),
  routing_status text not null
    check (routing_status in ('online','degraded','quota_blocked','auth_required','browser_only','offline','not_routable')),
  proof_ref text,
  joined_at timestamptz not null default now(),
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  check (
    (member_type='model' and model_id is not null)
    or
    (member_type='coordinator' and model_id is null)
  )
);

create unique index if not exists idx_members_model_id_unique
  on thoth_mesa.members(model_id)
  where model_id is not null;

create index if not exists idx_members_status
  on thoth_mesa.members(participation_status,routing_status);

alter table thoth_mesa.members enable row level security;

do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant select,insert,update on thoth_mesa.members to service_role;
  end if;
end $$;
