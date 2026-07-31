# Certifica Fácil

MVP de emissão e validação de certificados para ligas acadêmicas — leve, gratuito e simples de manter.
Inspirado na documentação técnica de um sistema baseado em Google Apps Script, mas reescrito do zero
com uma arquitetura serverless que roda inteira em free tiers.

## Stack

- **Next.js (App Router)** — frontend + backend (API Routes) no mesmo projeto → deploy único na Vercel
- **Supabase** — Postgres (banco), Storage (PDFs) e Auth, tudo no free tier
- **@react-pdf/renderer** — gera o PDF programaticamente, sem navegador headless (leve o suficiente para função serverless)
- **qrcode** — gera o QR Code de validação
- **Resend** *(opcional, a integrar)* — envio de e-mail transacional

## Por que essa arquitetura é mais simples que a original

A documentação original (Google Apps Script) usava Google Docs/Sheets como banco e motor de
templates, com limite de 6 min de execução por script. Aqui trocamos por:

| Original | Aqui | Ganho |
|---|---|---|
| Google Sheets como "banco" | Postgres (Supabase) | Consultas indexadas, sem limite de linhas de planilha |
| Google Docs + cópia de template | `@react-pdf/renderer` | PDF gerado em memória, sem cota de API do Google |
| MailApp/GmailApp (100–1500/dia) | Resend (3.000/mês grátis) | Sem cota diária baixa |
| Nenhuma fila / RBAC | Loop sequencial simples | Suficiente para lotes de dezenas/centenas — sem a complexidade de filas (SQS/Redis) que o público industrial exigiria |

## Passo a passo para rodar

### 1. Criar o projeto no Supabase (gratuito)
1. Crie uma conta em https://supabase.com e um novo projeto.
2. Vá em **SQL Editor** e rode o conteúdo de `supabase/schema.sql`.
3. Vá em **Storage** e crie um bucket chamado `certificates` (pode deixar privado — a validação pública usa signed URLs temporárias).
4. Vá em **Project Settings > API** e copie: `Project URL`, `anon public key`, `service_role key`.

### 2. Configurar variáveis de ambiente
```bash
cp .env.example .env.local
# preencha com os valores do Supabase
```

### 3. Rodar localmente
```bash
npm install
npm run dev
```
Acesse `http://localhost:3000/validar` para ver a página pública de validação.

### 4. Deploy gratuito
1. Suba o projeto para um repositório no GitHub.
2. Importe o repositório na [Vercel](https://vercel.com) (free tier).
3. Configure as mesmas variáveis de ambiente do `.env.local` no painel da Vercel.
4. Atualize `NEXT_PUBLIC_APP_URL` para a URL final (ex: `https://certifica-facil.vercel.app`) — ela é usada dentro do QR Code.

## Estrutura do projeto

```
src/
  app/
    validar/page.tsx              → página pública de validação
    dashboard/                    → (a construir) painel do admin da liga
    api/
      participants/import/route.ts  → importação de participantes via CSV
      certificates/generate/route.ts → geração em lote (PDF + hash + QR + storage)
      validate/route.ts             → endpoint consultado pela página /validar
  lib/
    supabase/client.ts   → cliente para uso no navegador (chave pública)
    supabase/server.ts   → cliente para uso nas API Routes (chave secreta)
    certificates/
      hash.ts             → gera o código de validação não-sequencial
      qrcode.ts            → gera o QR Code apontando para /validar
      CertificateTemplate.tsx → layout visual do PDF
supabase/
  schema.sql            → schema completo do banco (rodar no SQL Editor)
```

## O que falta para um MVP funcional completo (próximos passos sugeridos)

1. **Autenticação do admin** — Supabase Auth (email/senha ou magic link) protegendo `/dashboard` e as API Routes de escrita.
2. **Telas do dashboard** — formulário de criar evento, upload de CSV, botão "gerar certificados", listagem de status.
3. **Envio de e-mail** — endpoint que usa o Resend para notificar cada participante após a geração.
4. **Componente de import CSV no frontend** — hoje a rota `/api/participants/import` já funciona via multipart/form-data; falta a tela que faz esse upload.

## O que foi deliberadamente deixado de fora da v1

- Assinatura digital ICP-Brasil/Autentique (só necessária para documentos de SST/eSocial)
- Fila de processamento (SQS/Redis) — desnecessária para lotes de dezenas/centenas de certificados
- Multi-tenant / múltiplas organizações
- Editor visual drag-and-drop de template (o layout é um componente React fixo em `CertificateTemplate.tsx`)
