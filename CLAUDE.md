# CLAUDE.md

Este arquivo dá contexto ao Claude Code sobre o projeto **Certifica Fácil**. Leia isto
antes de propor mudanças de arquitetura — várias decisões aqui foram deliberadas e
descartaram alternativas mais "óbvias" por razões específicas explicadas abaixo.

> **Atualização importante (v2 deste documento):** o projeto deixou de ser uma ferramenta
> single-tenant para uma única liga. Agora é pensado desde já como **multi-tenant, com
> possibilidade de virar SaaS no futuro**. Isso muda o schema do banco, a autenticação e o
> isolamento de dados. Ver seção "Modelo multi-tenant" abaixo — ela substitui qualquer
> suposição de single-tenant que possa aparecer em código ou histórico anterior do projeto.
> **O código-fonte atual (schema.sql e API routes) ainda NÃO reflete essa mudança** — foi
> construído quando o projeto era single-tenant. Ver "Migração pendente" no fim deste arquivo.

## O que é o projeto

Plataforma **multi-tenant** para **emissão e validação pública de certificados digitais**,
voltada para **ligas acadêmicas, universidades e organizações de extensão** em geral — não
apenas uma liga específica. Múltiplas organizações (clientes) usam a mesma plataforma, cada
uma com seus próprios eventos e participantes, com dados isolados entre si. Fluxo central: uma
organização cadastra um evento/curso, importa uma lista de participantes (CSV), gera
certificados em lote (PDF com hash único + QR Code), e qualquer pessoa pode validar a
autenticidade de um certificado numa página pública, sem login.

### Origem / inspiração

O projeto foi inspirado numa documentação técnica (`Documentação_Técnica_de_Sistema.pdf`,
disponível nos arquivos do projeto) que descreve um sistema real baseado 100% no ecossistema
Google (Google Sheets como banco, Google Apps Script como backend, Google Docs como motor de
template), voltado para o mercado corporativo/industrial de Goiás (treinamentos de SST, normas
regulamentadoras NR-18/33/35, integração com Autentique/ICP-Brasil para assinatura jurídica).
Esse documento original já descrevia um modelo multi-tenant com RBAC (Admin Global /
Organizador / Avaliador / Participante) — o "Certifica Fácil" está se aproximando desse
desenho, mas continua deliberadamente mais simples em outros pontos (ver "O que continua
cortado" abaixo).

## Requisito não-negociável do dono do projeto

> "Desejo desenvolver uma aplicação web leve, rápida e que consiga rodar sem gastos... o
> desenvolvimento dessa aplicação DEVE ser simples e rápida."

Isso continua sendo o critério de decisão para qualquer dúvida de arquitetura: **entre uma
solução mais "correta"/escalável e uma mais simples/gratuita, escolha a mais simples**, a
menos que o dono do projeto peça o contrário. Multi-tenant não é uma licença para reintroduzir
toda a complexidade da documentação original (filas, ICP-Brasil, editor visual) — apenas o
isolamento de dados entre organizações e os 3 níveis de login abaixo é escopo aprovado por
enquanto.

## Modelo multi-tenant e níveis de acesso (decisão confirmada com o dono do projeto)

### Perfis de login (3 níveis para a v1)

| Perfil | Escopo | O que faz |
|---|---|---|
| **Platform Admin** (super admin) | Global, todas as organizações | Você. Gerencia organizações na plataforma (visualizar, suspender). Não tem tela de auto-cadastro — conta criada manualmente (via Supabase dashboard ou seed). |
| **Org Admin** | Uma organização | O usuário-cliente da liga/universidade. Cadastra eventos, importa participantes, gera e revoga certificados da própria organização. Não enxerga dados de outras organizações. |
| **Participant** | Global (não preso a uma organização) | Login **opcional** — a validação pública já funciona sem login. Quando logado, pode ver o histórico de todos os certificados recebidos, de qualquer organização, num só lugar (já que o cadastro de participante é global — ver abaixo). |

### Cadastro de organizações: autoatendimento (self-serve)

Qualquer pessoa pode criar uma conta e, no mesmo fluxo, criar sua própria organização — sem
aprovação manual do Platform Admin. Implicações técnicas:
- Precisa de uma tela/rota de "criar organização" que, ao ser concluída, grava a organização
  E marca o usuário autenticado como `org_admin` dessa organização — numa única operação
  atômica (evitar estado inconsistente de "usuário sem organização" ou "organização sem
  admin").
- Como qualquer usuário autenticado pode criar uma organização, a policy de RLS de `insert` em
  `organizations` deve permitir isso para qualquer usuário logado (não só platform_admin) —
  mas o `insert` em `events`/`participants`/etc. continua restrito ao `org_id` do próprio
  usuário.

### Participantes são uma identidade global, não por organização

Uma pessoa com o mesmo e-mail pode ser participante de eventos de organizações diferentes
(ex: fez um curso na liga de Medicina e outro na de Engenharia) e isso deve aparecer como o
**mesmo** participante, não um cadastro duplicado por organização. Isso já era como a tabela
`participants` funcionava no schema original — a mudança real é que agora ela é **compartilhada
entre organizações de propósito**, não uma limitação a ser corrigida depois.

Consequência prática: a tabela `participants` **não tem `org_id`**. Quem tem `org_id` é
`events` (e, por herança lógica através de `inscriptions`, os certificados). O isolamento
multi-tenant protege "quem pode ver/gerenciar os eventos e certificados de qual organização",
não "quem é a pessoa por trás de um e-mail".

## Stack e por que cada peça foi escolhida

| Peça | Escolha | Por quê |
|---|---|---|
| Framework | **Next.js 15+ (App Router)**, TypeScript, `src/` dir | Frontend + backend (API Routes) no mesmo projeto = um único deploy na Vercel. O dono do projeto tem experiência com React/Vite; Vite puro foi descartado porque é só SPA — não tem onde rodar geração de PDF, cálculo de hash, nem guardar a `service_role key` do Supabase com segurança. |
| Estilo | **Tailwind CSS v4** | Já vem no scaffold do `create-next-app`, zero configuração extra. |
| Banco de dados | **Supabase (Postgres)** free tier | Substitui o Google Sheets do sistema original. Ganha índices, integridade referencial e não tem limite de "linhas de planilha". Também é a base do isolamento multi-tenant via RLS (ver abaixo). |
| Storage de arquivos | **Supabase Storage** (bucket `certificates`) | Mesma conta do banco — evita configurar AWS S3 separadamente. |
| Autenticação | **Supabase Auth** — agora **obrigatória desde já** (deixou de ser "ainda não implementada"), pois é a peça que sustenta os 3 níveis de login e o isolamento entre organizações | Mesma razão acima: tudo numa conta só. Usa email/senha ou magic link — não precisa de nada mais sofisticado. |
| Geração de PDF | **`@react-pdf/renderer`** | Desenha o PDF programaticamente em memória, SEM navegador headless. Puppeteer/Playwright exigem muita RAM/CPU por instância e não rodam bem em free tier serverless. Para o volume esperado (dezenas/centenas de certificados por lote, não milhares simultâneos), `@react-pdf/renderer` é suficiente e muito mais leve. **Não trocar por Puppeteer sem um motivo forte.** |
| QR Code | **`qrcode`** (npm) | Gera o QR Code como data URL base64, embutido direto no PDF. |
| Hash de validação | **`crypto` nativo do Node** (SHA-256 truncado + UUID) | Não-sequencial e não-previsível. |
| Import de CSV | **`papaparse`** | Parsing simples de CSV no backend (API route), com `zod` validando cada linha. |
| Validação de schema | **`zod`** | Usado nas API routes para validar payloads. |
| E-mail transacional | **Resend** (planejado, ainda não integrado) | Free tier de 3.000 e-mails/mês. Substitui o `MailApp`/`GmailApp` do Google (cota de 100–1.500 envios/dia). |
| Hospedagem | **Vercel** (free tier) | Deploy automático via git push. |

### Regra de segurança importante

Existem DOIS clientes Supabase no projeto e eles NÃO são intercambiáveis:

- `src/lib/supabase/client.ts` → chave **anon/pública**. Só em código que roda no
  **navegador** (`"use client"`). Com multi-tenant, a maior parte das leituras autenticadas
  deve passar por aqui, respeitando RLS — não pela chave de service role.
- `src/lib/supabase/server.ts` → **`service_role` key**, ignora Row Level Security. Só em
  **API Routes** (`src/app/api/**/route.ts`) e só quando a operação realmente precisa
  contornar RLS (ex: geração de certificado em lote, que escreve em nome do sistema).
  **Nunca importar em componente client.**
- Com multi-tenant, o risco de vazar dados entre organizações por engano é maior. Qualquer
  rota nova de API deve **sempre** filtrar explicitamente por `org_id` do usuário autenticado
  antes de ler/escrever — não confiar apenas em RLS quando a rota usa `service_role`, já que
  essa chave ignora RLS por definição.

## Esboço do schema multi-tenant (alvo — ver "Migração pendente" para o estado real do código)

```
organizations
  id uuid pk
  name text
  created_at

profiles                          -- espelha auth.users do Supabase, guarda role e org
  id uuid pk (= auth.users.id)
  email text
  full_name text
  role text                       -- 'platform_admin' | 'org_admin' | 'participant'
  org_id uuid null → organizations.id   -- null para platform_admin e participant; obrigatório para org_admin
  participant_id uuid null → participants.id  -- preenchido se um participant também tiver login
  created_at

participants                      -- identidade GLOBAL, sem org_id de propósito
  id uuid pk
  full_name text
  cpf text null
  email text (unique)
  created_at

events                            -- agora pertence a uma organização
  id uuid pk
  org_id uuid → organizations.id  -- NOVO campo obrigatório
  title text
  workload_hours int
  start_date date
  end_date date
  instructor text
  location text
  created_at

inscriptions                      -- inalterado na forma, isolamento herdado via events.org_id
  id uuid pk
  event_id uuid → events.id
  participant_id uuid → participants.id
  status text                     -- pending | issued | revoked

certificates                      -- inalterado
  id uuid pk
  inscription_id uuid → inscriptions.id
  validation_hash text unique
  pdf_path text
  status text                     -- valid | revoked
  issued_at timestamptz

validation_logs                   -- inalterado
```

### Estratégia de isolamento (RLS)

- `profiles.org_id` é a fonte da verdade de "a qual organização este usuário pertence".
- Policies em `events` (e por herança lógica, tudo que depende de `event_id`): um `org_admin`
  só enxerga/edita linhas onde `events.org_id = (select org_id from profiles where id = auth.uid())`.
  Um `platform_admin` enxerga tudo (policy adicional checando `role = 'platform_admin'`).
- `participants`: leitura ampla é aceitável (é a identidade global), mas escrita/leitura de
  dados sensíveis (CPF completo, por exemplo) deve continuar passando pelas API Routes com
  mascaramento, como já documentado na seção de LGPD do PDF original.
- `organizations`: qualquer usuário autenticado pode fazer `insert` (fluxo de self-serve).
  `select`/`update` restrito ao próprio `org_admin` daquela organização + `platform_admin`.

## Estrutura do projeto

```
certifica-facil/
├── CLAUDE.md                    ← este arquivo
├── README.md                    ← passo a passo de setup (Supabase, deploy)
├── .env.example                 ← variáveis de ambiente necessárias (copiar para .env.local)
├── supabase/
│   └── schema.sql                ← schema do Postgres — AINDA NO FORMATO SINGLE-TENANT, ver Migração pendente
└── src/
    ├── app/
    │   ├── page.tsx               ← home simples, aponta para /validar
    │   ├── layout.tsx              ← layout raiz (SEM next/font/google — ver nota abaixo)
    │   ├── globals.css             ← paleta de cores do produto (ver "Identidade visual")
    │   ├── validar/
    │   │   └── page.tsx            ← página pública de validação (client component)
    │   ├── dashboard/               ← AINDA VAZIA — painel do org_admin, é o próximo passo
    │   └── api/
    │       ├── participants/import/route.ts    ← POST multipart: importa CSV (precisa passar a filtrar/gravar por org_id)
    │       ├── certificates/generate/route.ts   ← POST { eventId }: gera certificados em lote
    │       └── validate/route.ts                 ← GET ?hash=...: consultado por /validar
    └── lib/
        ├── supabase/
        │   ├── client.ts            ← cliente browser (chave anon)
        │   └── server.ts            ← cliente servidor (chave service_role — NUNCA no client)
        └── certificates/
            ├── hash.ts               ← gera código de validação não-sequencial
            ├── qrcode.ts              ← gera QR Code (data URL) apontando para /validar?hash=
            └── CertificateTemplate.tsx ← layout visual do PDF (@react-pdf/renderer)
```

**Nota sobre fontes**: o `layout.tsx` foi deliberadamente alterado para NÃO usar
`next/font/google` (Geist/Geist Mono), pois `next build` busca as fontes em build-time e isso
falha em ambientes sem internet (ex: sandbox/CI restrito). Usando a stack de fontes do sistema.

## Identidade visual

Paleta definida em `src/app/globals.css`, usada tanto no PDF (`CertificateTemplate.tsx`) quanto
na página `/validar`:

- `--background: #0b1220` (azul-tinta profundo)
- `--surface: #121a2b`
- `--foreground: #e7ecf7`
- `--muted: #7c879e`
- `--accent: #3ddc97` (verde-selo — cor de destaque/CTA)

Deliberadamente evitado: fundo creme + serifada + terracota (`#D97757`), e fundo preto +
verde-ácido/vermelho — "defaults" visuais comuns em UI gerada por IA. Manter a paleta acima em
qualquer tela nova, incluindo as futuras telas de onboarding de organização e login.

## Variáveis de ambiente (`.env.local`, ver `.env.example`)

```
NEXT_PUBLIC_SUPABASE_URL              → Project Settings > API no Supabase
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY  → idem, chave pública
SUPABASE_SECRET_KEY                   → idem, chave secreta — NUNCA logar, NUNCA expor ao client
NEXT_PUBLIC_APP_URL                   → URL pública do app (usada dentro do QR Code gerado)
RESEND_API_KEY                        → ainda não usada no código, reservada para o envio de e-mail
```

## O que continua cortado da documentação original e por quê

Multi-tenant e os 3 níveis de login foram aprovados — isso NÃO reabre os itens abaixo:

- **Puppeteer/Playwright + Filas (SQS/Redis/BullMQ)**: só se justificam com volume de milhares
  de certificados simultâneos. Não é o caso ainda, mesmo multi-tenant.
- **Assinatura digital ICP-Brasil / integração Autentique**: exigência legal específica de
  documentos de SST. Fora de escopo até alguma organização-cliente pedir isso explicitamente.
- **Avaliador/Instrutor como perfil de login à parte**: a v1 tem só Platform Admin, Org Admin e
  Participant. Um quarto perfil (instrutor com acesso restrito a lançar notas/presença) fica
  para depois, se algum cliente pedir.
- **Envio via WhatsApp**: e-mail (Resend) resolve a distribuição sem custo adicional.
- **Editor visual drag-and-drop de template**: layout do certificado continua sendo um
  componente React fixo (`CertificateTemplate.tsx`). Personalização por organização (logo,
  cores) pode virar um TODO futuro, mas não um editor completo.
- **Planos pagos / cobrança (billing)**: multi-tenant aqui é sobre isolamento de dados, não
  sobre monetização ainda. Não implementar Stripe ou similar sem pedido explícito.

## Status atual do projeto

### Feito e testado no formato single-tenant (build passa: `npm run build` ✅)
- Schema do banco (versão single-tenant, sem `organizations`/`profiles`)
- Rota de import de participantes via CSV (`/api/participants/import`)
- Rota de geração de certificados em lote (`/api/certificates/generate`)
- Rota de validação pública (`/api/validate`)
- Página pública de validação (`/validar`)
- Template visual do PDF (`CertificateTemplate.tsx`)

### Migração pendente para o modelo multi-tenant (prioridade atual)
O código listado acima ainda assume uma única organização implícita. Antes de construir o
dashboard, a ordem recomendada é:

1. **Atualizar `supabase/schema.sql`**: adicionar `organizations`, `profiles`, e a coluna
   `org_id` em `events`; adicionar as policies de RLS descritas em "Estratégia de isolamento"
   acima.
2. **Configurar Supabase Auth** no projeto (e-mail/senha ou magic link) e criar o fluxo de
   signup que cria `profiles` + `organizations` atomicamente (ver seção de self-serve acima).
   Recomendado usar uma função Postgres (`security definer`) ou uma API Route com
   `service_role` para essa operação atômica, já que envolve duas tabelas.
3. **Atualizar `/api/participants/import` e `/api/certificates/generate`** para receberem o
   usuário autenticado, resolverem o `org_id` via `profiles`, e validarem que o `eventId`
   pertence àquela organização antes de agir (hoje essas rotas não checam organização nenhuma).
4. **Dashboard do Org Admin** (`src/app/dashboard/`, hoje vazia):
   - Fluxo de onboarding (criar organização no primeiro login)
   - Formulário de criar/editar evento (já implicitamente escopado ao `org_id` do usuário)
   - Tela de upload de CSV
   - Botão "Gerar certificados"
   - Listagem de eventos com status de emissão
5. **Painel do Platform Admin** (novo, `src/app/admin/` ou similar): listagem de organizações,
   básico por enquanto (visualizar, suspender). Sem tela de auto-cadastro — conta criada
   manualmente.
6. **Portal do Participante** (opcional para v1, pode ficar para depois): login simples que,
   ao autenticar, busca certificados pelo e-mail correspondente em `participants`.
7. **Envio de e-mail** via Resend após a geração de certificados.

### Não fazer sem discutir antes com o dono do projeto
- Trocar `@react-pdf/renderer` por Puppeteer/Playwright
- Adicionar fila de processamento (SQS/Redis/BullMQ)
- Adicionar assinatura digital jurídica (ICP-Brasil/Autentique)
- Adicionar um 4º nível de login (ex: Instrutor/Avaliador) sem pedido explícito
- Implementar cobrança/planos pagos
- Trocar Supabase por serviços separados (AWS S3 + banco à parte + Auth0, etc.)

## Setup local (resumo — detalhes completos no README.md)

```bash
npm install
cp .env.example .env.local   # preencher com dados do projeto Supabase
npm run dev
```

1. Criar projeto no supabase.com (free tier)
2. Rodar `supabase/schema.sql` no SQL Editor (⚠️ hoje ainda na versão single-tenant — ver
   "Migração pendente" antes de usar em produção)
3. Criar bucket `certificates` no Storage (pode ser privado)
4. Copiar URL + anon key + service_role key para `.env.local`

## Deploy

Vercel (free tier), importando o repositório do GitHub. Configurar as mesmas variáveis de
ambiente do `.env.local` no painel da Vercel, e atualizar `NEXT_PUBLIC_APP_URL` para a URL
final de produção (ela é usada dentro do QR Code gerado nos certificados).
