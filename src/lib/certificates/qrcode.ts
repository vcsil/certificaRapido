import QRCode from "qrcode";

export async function generateValidationQrCode(hash: string): Promise<string> {
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const validationUrl = `${baseUrl}/validar?hash=${hash}`;

  // Retorna a imagem já como data URL (base64), pronta para embutir no PDF
  return QRCode.toDataURL(validationUrl, { errorCorrectionLevel: "H", margin: 1 });
}
