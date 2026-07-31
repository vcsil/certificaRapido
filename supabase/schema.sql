-- ============================================================
-- Schema multi-tenant para Certifica Fácil
-- Rode este arquivo no SQL Editor do seu projeto Supabase
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- Organizações (tenants)
-- ------------------------------------------------------------
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Perfis: espelham auth.users, guardam role e organização.
-- A FK para participants é adicionada depois que a tabela existir.
-- ------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role text not null default 'participant', -- 'platform_admin' | 'org_admin' | 'participant'
  org_id uuid references organizations(id) on delete cascade, -- null p/ platform_admin e participant; obrigatório p/ org_admin
  participant_id uuid,
  created_at timestamptz not null default now(),
  constraint profiles_role_check check (role in ('platform_admin', 'org_admin', 'participant')),
  constraint profiles_org_admin_has_org check (role <> 'org_admin' or org_id is not null)
);

-- ------------------------------------------------------------
-- Eventos/cursos — agora pertencem a uma organização
-- ------------------------------------------------------------
create table events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  workload_hours integer not null,
  start_date date not null,
  end_date date not null,
  instructor text,
  location text,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Participantes — identidade GLOBAL (sem org_id de propósito).
-- email é unique: mesmo e-mail em organizações diferentes é a
-- MESMA pessoa. A rota de import (/api/participants/import) deve
-- fazer upsert por email, não insert puro.
-- ------------------------------------------------------------
create table participants (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  cpf text,
  email text not null unique,
  created_at timestamptz not null default now()
);

alter table profiles
  add constraint profiles_participant_id_fkey
  foreign key (participant_id) references participants(id) on delete set null;

-- Inscrição = vínculo entre participante e evento
create table inscriptions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  status text not null default 'pending', -- pending | issued | revoked
  created_at timestamptz not null default now(),
  unique (event_id, participant_id)
);

-- Certificado emitido
create table certificates (
  id uuid primary key default gen_random_uuid(),
  inscription_id uuid not null references inscriptions(id) on delete cascade,
  validation_hash text not null unique,
  pdf_path text, -- caminho no bucket do Supabase Storage
  status text not null default 'valid', -- valid | revoked
  issued_at timestamptz not null default now()
);

-- Log de consultas públicas (opcional, útil para auditoria/anti-abuso)
create table validation_logs (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid references certificates(id) on delete set null,
  accessed_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Índices
-- ------------------------------------------------------------
create index idx_events_org_id on events(org_id);
create index idx_profiles_org_id on profiles(org_id);
create index idx_certificates_hash on certificates(validation_hash);
create index idx_participants_email on participants(email);
create index idx_participants_cpf on participants(cpf);

-- ------------------------------------------------------------
-- Helpers para as policies de RLS.
-- security definer é necessário para evitar recursão infinita
-- quando uma policy de `profiles` precisa consultar a própria
-- tabela `profiles` (ex: checar se o usuário é platform_admin).
-- ------------------------------------------------------------
create or replace function current_profile_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function current_profile_org_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select org_id from profiles where id = auth.uid();
$$;

-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------
alter table organizations enable row level security;
alter table profiles enable row level security;
alter table events enable row level security;
alter table participants enable row level security;
alter table inscriptions enable row level security;
alter table certificates enable row level security;
alter table validation_logs enable row level security;

-- organizations: qualquer autenticado pode criar (fluxo self-serve).
-- select/update restrito ao próprio org_admin daquela organização + platform_admin.
create policy "insert organizacao autenticado"
  on organizations for insert
  to authenticated
  with check (true);

create policy "select organizacao propria"
  on organizations for select
  to authenticated
  using (
    current_profile_role() = 'platform_admin'
    or id = current_profile_org_id()
  );

create policy "update organizacao propria"
  on organizations for update
  to authenticated
  using (id = current_profile_org_id() and current_profile_role() = 'org_admin')
  with check (id = current_profile_org_id() and current_profile_role() = 'org_admin');

-- profiles: cada usuário vê/edita o próprio perfil; platform_admin vê todos
create policy "select proprio perfil"
  on profiles for select
  to authenticated
  using (id = auth.uid() or current_profile_role() = 'platform_admin');

create policy "update proprio perfil"
  on profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "insert proprio perfil"
  on profiles for insert
  to authenticated
  with check (id = auth.uid());

-- events: isolamento por organização
create policy "org admin gerencia eventos"
  on events for all
  to authenticated
  using (org_id = current_profile_org_id() or current_profile_role() = 'platform_admin')
  with check (org_id = current_profile_org_id() or current_profile_role() = 'platform_admin');

-- participants: identidade global — leitura ampla para autenticados;
-- escrita continua reservada às API Routes (service_role, ignora RLS).
create policy "select participantes"
  on participants for select
  to authenticated
  using (true);

-- inscriptions: isolamento herdado via events.org_id
create policy "org admin gerencia inscricoes"
  on inscriptions for all
  to authenticated
  using (
    current_profile_role() = 'platform_admin'
    or exists (
      select 1 from events
      where events.id = inscriptions.event_id
        and events.org_id = current_profile_org_id()
    )
  )
  with check (
    current_profile_role() = 'platform_admin'
    or exists (
      select 1 from events
      where events.id = inscriptions.event_id
        and events.org_id = current_profile_org_id()
    )
  );

-- certificates: leitura pública dos válidos (usada por /validar) +
-- gestão isolada por organização via inscriptions -> events.org_id
create policy "certificados validos publicos"
  on certificates for select
  using (status = 'valid');

create policy "org admin gerencia certificados"
  on certificates for all
  to authenticated
  using (
    current_profile_role() = 'platform_admin'
    or exists (
      select 1 from inscriptions
      join events on events.id = inscriptions.event_id
      where inscriptions.id = certificates.inscription_id
        and events.org_id = current_profile_org_id()
    )
  )
  with check (
    current_profile_role() = 'platform_admin'
    or exists (
      select 1 from inscriptions
      join events on events.id = inscriptions.event_id
      where inscriptions.id = certificates.inscription_id
        and events.org_id = current_profile_org_id()
    )
  );

-- validation_logs: sem policy para authenticated/anon —
-- só a service_role (API routes) acessa, igual ao comportamento anterior.
