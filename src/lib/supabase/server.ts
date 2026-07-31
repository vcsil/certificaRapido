import { createClient } from "@supabase/supabase-js";

// ATENÇÃO: este client usa a secret key, que ignora RLS.
// Só pode ser importado dentro de código que roda no servidor
// (API Routes em src/app/api/**), NUNCA em componentes client.
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SECRET_KEY!,
  { auth: { persistSession: false } }
);
