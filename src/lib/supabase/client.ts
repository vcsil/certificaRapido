import { createClient } from "@supabase/supabase-js";

// Usa a publishable key — segura para expor no navegador.
// Toda operação sensível (escrita, geração de certificado) acontece
// nas API Routes com a secret key, nunca aqui.
export const supabaseBrowser = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
);
