import { NextRequest, NextResponse } from "next/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { supabaseAdmin } from "@/lib/supabase/server";
import { generateValidationHash } from "@/lib/certificates/hash";
import { generateValidationQrCode } from "@/lib/certificates/qrcode";
import { CertificateTemplate } from "@/lib/certificates/CertificateTemplate";

const ORG_NAME = "Liga Acadêmica"; // troque pelo nome da sua liga, ou puxe da tabela organizations se criar uma

// Gera certificados para todas as inscrições "pending" de um evento.
// Body: { eventId: string }
export async function POST(req: NextRequest) {
  const { eventId } = await req.json();
  if (!eventId) {
    return NextResponse.json({ error: "Informe eventId." }, { status: 400 });
  }

  const { data: event, error: eventError } = await supabaseAdmin
    .from("events")
    .select("*")
    .eq("id", eventId)
    .single();

  if (eventError || !event) {
    return NextResponse.json({ error: "Evento não encontrado." }, { status: 404 });
  }

  const { data: inscriptions, error: inscError } = await supabaseAdmin
    .from("inscriptions")
    .select("id, participants(full_name, email)")
    .eq("event_id", eventId)
    .eq("status", "pending");

  if (inscError) {
    return NextResponse.json({ error: inscError.message }, { status: 500 });
  }

  if (!inscriptions || inscriptions.length === 0) {
    return NextResponse.json({ generated: 0, message: "Nenhuma inscrição pendente." });
  }

  const results: { participant: string; hash: string; status: string }[] = [];

  // Processa sequencialmente para não estourar memória da função serverless.
  // Para lotes muito grandes (milhares), divida em páginas/chamadas.
  for (const inscription of inscriptions) {
    const participant = (inscription as any).participants;
    try {
      const hash = generateValidationHash();
      const qrCodeDataUrl = await generateValidationQrCode(hash);

      const pdfBuffer = await renderToBuffer(
        CertificateTemplate({
          data: {
            participantName: participant.full_name,
            eventTitle: event.title,
            workloadHours: event.workload_hours,
            instructor: event.instructor,
            issuedAtLabel: new Date().toLocaleDateString("pt-BR"),
            validationHash: hash,
            qrCodeDataUrl,
            orgName: ORG_NAME,
          },
        })
      );

      const pdfPath = `certificates/${hash}.pdf`;
      const { error: uploadError } = await supabaseAdmin.storage
        .from("certificates")
        .upload(pdfPath, pdfBuffer, { contentType: "application/pdf", upsert: true });

      if (uploadError) throw new Error(uploadError.message);

      const { error: certError } = await supabaseAdmin.from("certificates").insert({
        inscription_id: inscription.id,
        validation_hash: hash,
        pdf_path: pdfPath,
        status: "valid",
      });
      if (certError) throw new Error(certError.message);

      await supabaseAdmin.from("inscriptions").update({ status: "issued" }).eq("id", inscription.id);

      results.push({ participant: participant.email, hash, status: "ok" });
    } catch (err: any) {
      results.push({ participant: participant?.email ?? "?", hash: "", status: `erro: ${err.message}` });
    }
  }

  return NextResponse.json({ generated: results.filter((r) => r.status === "ok").length, results });
}
