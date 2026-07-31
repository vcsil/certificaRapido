import { NextRequest, NextResponse } from "next/server";
import Papa from "papaparse";
import { z } from "zod";
import { supabaseAdmin } from "@/lib/supabase/server";

const rowSchema = z.object({
  nome: z.string().min(1),
  email: z.string().email(),
  cpf: z.string().optional().default(""),
});

// Espera um multipart/form-data com:
//  - "file": o CSV (colunas: nome;email;cpf)
//  - "eventId": uuid do evento já cadastrado
export async function POST(req: NextRequest) {
  const form = await req.formData();
  const file = form.get("file");
  const eventId = form.get("eventId");

  if (!(file instanceof File) || typeof eventId !== "string") {
    return NextResponse.json({ error: "Envie 'file' (CSV) e 'eventId'." }, { status: 400 });
  }

  const text = await file.text();
  const parsed = Papa.parse(text, { header: true, skipEmptyLines: true, delimiter: ";" });

  const errors: string[] = [];
  const validRows: z.infer<typeof rowSchema>[] = [];

  parsed.data.forEach((row: any, i: number) => {
    const result = rowSchema.safeParse({
      nome: row.nome?.trim(),
      email: row.email?.trim().toLowerCase(),
      cpf: row.cpf?.replace(/\D/g, ""),
    });
    if (result.success) validRows.push(result.data);
    else errors.push(`Linha ${i + 2}: ${result.error.issues.map((e) => e.message).join(", ")}`);
  });

  if (validRows.length === 0) {
    return NextResponse.json({ error: "Nenhuma linha válida encontrada.", details: errors }, { status: 400 });
  }

  // Upsert dos participantes (evita duplicar quem já existe por email)
  const { data: participants, error: upsertError } = await supabaseAdmin
    .from("participants")
    .upsert(
      validRows.map((r) => ({ full_name: r.nome, email: r.email, cpf: r.cpf || null })),
      { onConflict: "email", ignoreDuplicates: false }
    )
    .select("id, email");

  if (upsertError) {
    return NextResponse.json({ error: upsertError.message }, { status: 500 });
  }

  // Cria a inscrição (evento <-> participante) para cada um, ignorando duplicatas
  const inscriptions = participants!.map((p) => ({
    event_id: eventId,
    participant_id: p.id,
    status: "pending",
  }));

  const { error: inscriptionError } = await supabaseAdmin
    .from("inscriptions")
    .upsert(inscriptions, { onConflict: "event_id,participant_id", ignoreDuplicates: true });

  if (inscriptionError) {
    return NextResponse.json({ error: inscriptionError.message }, { status: 500 });
  }

  return NextResponse.json({
    imported: participants!.length,
    warnings: errors,
  });
}
