# CLAUDE.md

Este arquivo dá contexto ao Claude Code sobre o projeto **Certifica Fácil**. Leia isto
antes de propor mudanças de arquitetura — várias decisões aqui foram deliberadas e
descartaram alternativas mais "óbvias" por razões específicas explicadas abaixo.

## O que é o projeto

Plataforma web para **emissão e validação pública de certificados digitais**, feita sob
medida para **ligas acadêmicas e universidades** — não para o mercado corporativo/industrial.
Fluxo central: um organizador cadastra um evento/curso, importa uma lista de participantes
(CSV), gera certificados em lote (PDF com hash único + QR Code), e qualquer pessoa pode
validar a autenticidade de um certificado numa página pública, sem login.

### Origem / inspiração

O projeto foi inspirado numa documentação técnica (`Documentação_Técnica_de_Sistema.pdf`,
disponível nos arquivos do projeto) que descreve um sistema real baseado 100% no ecossistema
Google (Google Sheets como banco, Google Apps Script como backend, Google Docs como motor de
template), voltado para o mercado corporativo/industrial de Goiás (treinamentos de SST, normas
regulamentadoras NR-18/33/35, integração com Autentique/ICP-Brasil para assinatura jurídica).

**Este projeto NÃO é uma cópia dessa documentação.** É uma reinterpretação enxuta para um
público muito mais simples (ligas acadêmicas), que descarta deliberadamente boa parte da
complexidade do documento original. Ver seção "O que foi cortado e por quê" abaixo — isso
importa para não reintroduzir complexidade desnecessária "porque a documentação original tinha".

## Requisito não-negociável do dono do projeto

> "Desejo desenvolver uma aplicação web leve, rápida e que consiga rodar sem gastos... o
> desenvolvimento dessa aplicação DEVE ser simples e rápida."

Isso é o critério de decisão para qualquer dúvida de arquitetura daqui pra frente: **entre
uma solução mais "correta"/escalável e uma mais simples/gratuita, escolha a mais simples**,
a menos que o dono do projeto peça explicitamente o contrário. Este não é um produto SaaS
multi-tenant para vender a empresas — é uma ferramenta interna de uma liga acadêmica.

## Stack e por que cada peça foi escolhida

| Peça | Escolha | Por quê |
|---|---|---|
| Framework | **Next.js 15+ (App Router)**, TypeScript, `src/` dir | Frontend + backend (API Routes) no mesmo projeto = um único deploy na Vercel. O dono do projeto tem experiência com React/Vite; Vite puro foi descartado porque é só SPA — não tem onde rodar geração de PDF, cálculo de hash, nem guardar a `service_role key` do Supabase com segurança. |
| Estilo | **Tailwind CSS v4** | Já vem no scaffold do `create-next-app`, zero configuração extra. |
| Banco de dados | **Supabase (Postgres)** free tier | Substitui o Google Sheets do sistema original. Ganha índices, integridade referencial e não tem limite de "linhas de planilha". |
| Storage de arquivos | **Supabase Storage** (bucket `certificates`) | Mesma conta do banco — evita ter que configurar AWS S3 separadamente (menos contas, menos chaves, menos custo cognitivo). |
| Autenticação | **Supabase Auth** (ainda não implementada, ver TODO) | Mesma razão acima: tudo numa conta só. |
| Geração de PDF | **`@react-pdf/renderer`** | Desenha o PDF programaticamente em memória, SEM navegador headless. Isso é uma escolha crítica: Puppeteer/Playwright (usados na "arquitetura escalável" da documentação original) exigem muita RAM/CPU por instância e não rodam bem em free tier de função serverless (ex: Vercel Hobby). Para o volume de uma liga acadêmica (dezenas/centenas de certificados por vez, não milhares simultâneos), `@react-pdf/renderer` é suficiente e MUITO mais leve. **Não trocar por Puppeteer sem um motivo forte.** |
| QR Code | **`qrcode`** (npm) | Gera o QR Code como data URL base64, embutido direto no PDF. |
| Hash de validação | **`crypto` nativo do Node** (SHA-256 truncado + UUID) | Não-sequencial e não-previsível, como no documento original — mas sem nenhuma dependência externa. |
| Import de CSV | **`papaparse`** | Parsing simples de CSV no backend (API route), com `zod` validando cada linha. |
| Validação de schema | **`zod`** | Usado nas API routes para validar payloads (ex: linhas do CSV). |
| E-mail transacional | **Resend** (planejado, ainda não integrado) | Free tier de 3.000 e-mails/mês, API simples via HTTP. Substitui o `MailApp`/`GmailApp` do Google (que tem cota de 100–1.500 envios/dia). |
| Hospedagem | **Vercel** (free tier) | Deploy automático via git push, zero configuração de servidor. |

### Regra de segurança importante

Existem DOIS clientes Supabase no projeto e eles NÃO são intercambiáveis:

- `src/lib/supabase/client.ts` → usa a chave **anon/pública**. Só pode ser importado em
  código que roda no **navegador** (componentes `"use client"`).
- `src/lib/supabase/server.ts` → usa a **`service_role` key**, que ignora Row Level Security.
  Só pode ser importado dentro de **API Routes** (`src/app/api/**/route.ts`) ou outro código
  que roda exclusivamente no servidor. **Nunca importar `server.ts` num componente client** —
  isso vazaria a chave secreta para o navegador do usuário.

## O que foi cortado da documentação original e por quê

Não reintroduzir isso sem o dono do projeto pedir explicitamente:

- **Puppeteer/Playwright + Filas (SQS/Redis/BullMQ)**: existiam no documento original para
  aguentar milhares de emissões simultâneas de múltiplas empresas-cliente. Uma liga acadêmica
  gera certificados em lotes esporádicos (fim de semestre/evento) — não precisa de fila.
- **Assinatura digital ICP-Brasil / integração Autentique**: exigência legal específica de
  documentos de Saúde e Segurança do Trabalho (SST) no mercado de trabalho. Certificado de
  liga acadêmica não tem essa exigência.
- **RBAC multi-tenant complexo** (Admin Global / Organizador / Avaliador / Participante):
  simplificado para essencialmente um único perfil de admin (a liga) por enquanto. Ver TODO
  sobre autenticação.
- **Envio via WhatsApp**: cortado por depender de custos por template na API oficial da Meta
  em escala. E-mail (Resend) resolve a distribuição sem custo adicional.
- **Editor visual drag-and-drop de template**: o layout do certificado é hoje um componente
  React fixo (`CertificateTemplate.tsx`). Construir um editor visual é uma quantidade grande
  de trabalho de frontend que não se justifica para a v1.

## Estrutura do projeto

```
certifica-facil/
├── CLAUDE.md                    ← este arquivo
├── README.md                    ← passo a passo de setup (Supabase, deploy)
├── .env.example                 ← variáveis de ambiente necessárias (copiar para .env.local)
├── supabase/
│   └── schema.sql                ← schema completo do Postgres (rodar no SQL Editor do Supabase)
└── src/
    ├── app/
    │   ├── page.tsx               ← home simples, aponta para /validar
    │   ├── layout.tsx              ← layout raiz (SEM next/font/google — ver nota abaixo)
    │   ├── globals.css             ← paleta de cores do produto (ver "Identidade visual")
    │   ├── validar/
    │   │   └── page.tsx            ← página pública de validação (client component)
    │   ├── dashboard/               ← AINDA VAZIA — painel do admin, é o próximo passo (ver TODO)
    │   └── api/
    │       ├── participants/import/route.ts    ← POST multipart: importa CSV de participantes
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
`next/font/google` (Geist/Geist Mono). Isso porque o `next build` tenta buscar as fontes do
Google em build-time, o que falha em ambientes sem acesso à internet (ex: CI restrito, sandbox).
Está usando a stack de fontes do sistema. Se quiser reintroduzir fontes do Google, tudo bem em
ambientes com internet liberada — só ciente do trade-off.

## Identidade visual

Paleta definida em `src/app/globals.css`, usada tanto no PDF (`CertificateTemplate.tsx`) quanto
na página `/validar`, para o produto ter uma identidade coesa e não genérica:

- `--background: #0b1220` (azul-tinta profundo)
- `--surface: #121a2b`
- `--foreground: #e7ecf7`
- `--muted: #7c879e`
- `--accent: #3ddc97` (verde-selo — usado como cor de destaque/CTA)

Deliberadamente evitado: fundo creme + serifada + terracota (`#D97757`), e fundo preto +
verde-ácido/vermelho — são os "defaults" visuais mais comuns em UI gerada por IA. Manter a
paleta acima em qualquer tela nova.

## Schema do banco (resumo — ver `supabase/schema.sql` para o SQL completo)

```
organizations (não criada ainda — hoje o projeto assume uma liga só, ver TODO)
events            → evento/curso: title, workload_hours, start_date, end_date, instructor, location
participants      → full_name, cpf (opcional), email (unique-ish via upsert)
inscriptions      → vínculo evento <-> participante, status: pending | issued | revoked
certificates      → inscription_id, validation_hash (unique), pdf_path, status: valid | revoked
validation_logs   → log de consultas públicas (auditoria, hoje pouco usado)
```

RLS (Row Level Security) está habilitado em todas as tabelas. A policy pública hoje permite
apenas `select` em `certificates` com `status = 'valid'` — toda escrita passa pelas API Routes
usando a `service_role` key (que ignora RLS).

## Variáveis de ambiente (`.env.local`, ver `.env.example`)

```
NEXT_PUBLIC_SUPABASE_URL          → Project Settings > API no Supabase
NEXT_PUBLIC_SUPABASE_ANON_KEY     → idem, chave pública
SUPABASE_SERVICE_ROLE_KEY         → idem, chave secreta — NUNCA logar, NUNCA expor ao client
NEXT_PUBLIC_APP_URL                → URL pública do app (usada dentro do QR Code gerado)
RESEND_API_KEY                     → ainda não usada no código, reservada para o envio de e-mail
```

## Status atual do projeto

### Feito e testado (build passa: `npm run build` ✅)
- Schema do banco completo
- Rota de import de participantes via CSV (`/api/participants/import`)
- Rota de geração de certificados em lote (`/api/certificates/generate`) — gera hash, QR,
  PDF, salva no Storage, registra no banco, atualiza status da inscrição
- Rota de validação pública (`/api/validate`)
- Página pública de validação (`/validar`) — busca por hash, mostra dados mascarados
- Template visual do PDF (`CertificateTemplate.tsx`)

### TODO — próximos passos recomendados, nessa ordem
1. **Dashboard do organizador** (`src/app/dashboard/`): hoje é uma pasta vazia. Precisa de:
   - Formulário de criar/editar evento
   - Tela de upload de CSV (chama `/api/participants/import`, que já funciona)
   - Botão "Gerar certificados" (chama `/api/certificates/generate`, que já funciona)
   - Listagem de eventos com status de emissão
2. **Autenticação do admin**: proteger `/dashboard` e as API routes de escrita com Supabase
   Auth (email/senha ou magic link é suficiente — não precisa de RBAC granular por enquanto).
3. **Envio de e-mail**: endpoint novo (`/api/certificates/notify` ou dentro da própria rota de
   `generate`) usando Resend para notificar cada participante com o link de download depois
   da geração.
4. **Componente de import CSV no frontend**: a rota de backend já existe e funciona via
   `multipart/form-data`; falta a tela que monta esse form e faz o upload.

### Não fazer sem discutir antes com o dono do projeto
- Trocar `@react-pdf/renderer` por Puppeteer/Playwright
- Adicionar fila de processamento (SQS/Redis/BullMQ)
- Adicionar multi-tenancy / múltiplas organizações
- Adicionar assinatura digital jurídica (ICP-Brasil/Autentique)
- Trocar Supabase por uma combinação de serviços separados (AWS S3 + banco gerenciado à parte
  + Auth0, etc.) — o valor do Supabase aqui é justamente centralizar tudo numa conta gratuita

## Setup local (resumo — detalhes completos no README.md)

```bash
npm install
cp .env.example .env.local   # preencher com dados do projeto Supabase
npm run dev
```

1. Criar projeto no supabase.com (free tier)
2. Rodar `supabase/schema.sql` no SQL Editor
3. Criar bucket `certificates` no Storage (pode ser privado)
4. Copiar URL + anon key + service_role key para `.env.local`

## Deploy

Vercel (free tier), importando o repositório do GitHub. Configurar as mesmas variáveis de
ambiente do `.env.local` no painel da Vercel, e atualizar `NEXT_PUBLIC_APP_URL` para a URL
final de produção (ela é usada dentro do QR Code gerado nos certificados).
