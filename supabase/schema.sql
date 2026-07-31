-- ============================================================
-- Schema multi-tenant para Certifica Fácil
-- Rode este arquivo INTEIRO no SQL Editor do seu projeto Supabase.
-- Se você já rodou uma versão anterior deste schema, apague as
-- tabelas antigas primeiro (ver README.md / CLAUDE.md, seção de
-- reset do banco) antes de rodar este arquivo.
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
-- Criação automática de perfil no signup.
-- Sem isso, um usuário criado via Supabase Auth não ganha uma
-- linha correspondente em `profiles` (e não pode mais criar essa
-- linha ele mesmo — ver revoke/grant de `profiles` mais abaixo).
-- ------------------------------------------------------------
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ------------------------------------------------------------
-- Criação de organização + promoção atômica a org_admin.
-- security definer permite que esta função escreva `role` e
-- `org_id` em `profiles` mesmo o client não tendo permissão
-- direta de UPDATE nessas colunas (ver grant/revoke abaixo).
-- Chamar via supabase.rpc('create_organization_and_become_admin',
-- { org_name: '...' }) no frontend.
-- ------------------------------------------------------------
create or replace function create_organization_and_become_admin(org_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org_id uuid;
begin
  if exists (select 1 from profiles where id = auth.uid() and org_id is not null) then
    raise exception 'Usuário já pertence a uma organização.';
  end if;

  insert into organizations (name) values (org_name) returning id into new_org_id;

  update profiles
    set role = 'org_admin', org_id = new_org_id
    where id = auth.uid();

  return new_org_id;
end;
$$;

grant execute on function create_organization_and_become_admin(text) to authenticated;

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

-- organizations: o INSERT direto do client fica bloqueado — a
-- criação de organização passa exclusivamente pela função
-- create_organization_and_become_admin (acima), que já garante
-- que ela nasce vinculada a um org_admin. Sem policy de insert
-- para "authenticated", nenhuma linha nova entra fora da função.
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

-- profiles: leitura do próprio perfil (ou tudo, se platform_admin).
-- ATENÇÃO: não existe policy de INSERT nem de UPDATE liberada para
-- authenticated aqui de propósito. `role` e `org_id` são as colunas
-- que definem privilégio no sistema inteiro — se o client pudesse
-- escrever nelas livremente, qualquer usuário autenticado poderia
-- se autopromover a platform_admin ou assumir outra organização.
-- A única forma de sair de "participant" é via
-- create_organization_and_become_admin() (org_admin) ou uma ação
-- manual do platform_admin (ver nota abaixo).

create policy "select proprio perfil"
  on profiles for select
  to authenticated
  using (id = auth.uid() or current_profile_role() = 'platform_admin');

-- Só a coluna full_name pode ser editada diretamente pelo dono do
-- perfil. role/org_id/participant_id ficam de fora do grant.
revoke update on profiles from authenticated;
grant update (full_name) on profiles to authenticated;

create policy "update proprio nome"
  on profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- platform_admin promovendo/editando qualquer perfil (ex: suspender
-- uma organização mudando o role de alguém) continua possível via
-- service_role nas API Routes, que ignora RLS por definição — não
-- precisa de policy adicional aqui para isso.

-- events: isolamento por organização
create policy "org admin gerencia eventos"
  on events for all
  to authenticated
  using (org_id = current_profile_org_id() or current_profile_role() = 'platform_admin')
  with check (org_id = current_profile_org_id() or current_profile_role() = 'platform_admin');

-- participants: identidade global, mas a LEITURA não pode ser
-- irrestrita (CPF e e-mail de todo mundo na plataforma). Só enxerga
-- um participante quem: é platform_admin, é o próprio participante
-- logado, ou é org_admin de uma organização que tem esse participante
-- inscrito em algum evento seu.
create policy "select participantes acessiveis"
  on participants for select
  to authenticated
  using (
    current_profile_role() = 'platform_admin'
    or id = (select participant_id from profiles where id = auth.uid())
    or exists (
      select 1 from inscriptions
      join events on events.id = inscriptions.event_id
      where inscriptions.participant_id = participants.id
        and events.org_id = current_profile_org_id()
    )
  );

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

-- ------------------------------------------------------------
-- Nota sobre o primeiro platform_admin
-- ------------------------------------------------------------
-- Não existe fluxo de auto-cadastro para platform_admin (é você).
-- Depois de criar sua própria conta pelo signup normal (o que a
-- deixa como 'participant' por padrão via trigger), promova-se
-- manualmente UMA vez, direto no SQL Editor (que roda como
-- superusuário do Postgres e ignora RLS):
--
--   update profiles set role = 'platform_admin' where email = 'seu-email@exemplo.com';
