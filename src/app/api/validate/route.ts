import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/server";

function maskEmail(email: string) {
  const [user, domain] = email.split("@");
  if (!user || !domain) return email;
  return `${user.slice(0, 2)}${"*".repeat(Math.max(user.length - 2, 1))}@${domain}`;
}

export async function GET(req: NextRequest) {
  const hash = req.nextUrl.searchParams.get("hash")?.toUpperCase().trim();

  if (!hash) {
    return NextResponse.json({ error: "Informe o parâmetro 'hash'." }, { status: 400 });
  }

  const { data: certificate, error } = await supabaseAdmin
    .from("certificates")
    .select(
      "validation_hash, status, issued_at, pdf_path, inscriptions(events(title, workload_hours, start_date, end_date, instructor), participants(full_name, email))"
    )
    .eq("validation_hash", hash)
    .maybeSingle();

  if (error || !certificate) {
    return NextResponse.json({ valid: false, message: "Certificado não encontrado." }, { status: 404 });
  }

  // Log de auditoria (não bloqueante)
  supabaseAdmin
    .from("validation_logs")
    .insert({ certificate_id: null }) // opcional: relacionar via segunda query se quiser o id
    .then(() => {});

  const inscription = (certificate as any).inscriptions;
  const event = inscription?.events;
  const participant = inscription?.participants;

  const { data: signedUrl } = await supabaseAdmin.storage
    .from("certificates")
    .createSignedUrl(certificate.pdf_path, 60 * 10); // 10 min

  return NextResponse.json({
    valid: certificate.status === "valid",
    status: certificate.status,
    hash: certificate.validation_hash,
    issuedAt: certificate.issued_at,
    participantName: participant?.full_name,
    participantEmail: maskEmail(participant?.email ?? ""),
    event: {
      title: event?.title,
      workloadHours: event?.workload_hours,
      instructor: event?.instructor,
    },
    downloadUrl: signedUrl?.signedUrl ?? null,
  });
}
