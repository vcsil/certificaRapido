-- ============================================================
-- Schema simplificado para Certifica Fácil
-- Rode este arquivo no SQL Editor do seu projeto Supabase
-- ============================================================

create extension if not exists "pgcrypto";

-- Eventos/cursos da liga acadêmica
create table events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  workload_hours integer not null,
  start_date date not null,
  end_date date not null,
  instructor text,
  location text,
  created_at timestamptz not null default now()
);

-- Participantes (podem se repetir entre eventos diferentes)
create table participants (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  cpf text,
  email text not null,
  created_at timestamptz not null default now()
);

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

-- Índices para busca rápida na validação pública
create index idx_certificates_hash on certificates(validation_hash);
create index idx_participants_email on participants(email);
create index idx_participants_cpf on participants(cpf);

-- Row Level Security: bloqueia acesso direto do navegador.
-- Toda escrita/leitura sensível passa pelas API Routes (que usam a service_role key).
alter table events enable row level security;
alter table participants enable row level security;
alter table inscriptions enable row level security;
alter table certificates enable row level security;
alter table validation_logs enable row level security;

-- Leitura pública apenas do necessário para a página de validação
-- (a API route de validação usa service_role e ignora RLS, mas deixamos
-- esta policy como fallback documentado caso queira consultar direto do client)
create policy "Certificados válidos são publicamente consultáveis"
  on certificates for select
  using (status = 'valid');
