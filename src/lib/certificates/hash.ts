import { randomUUID, createHash } from "crypto";

/**
 * Gera um código de validação curto, alfanumérico e não-previsível.
 * Combina um UUID aleatório (evita colisão) com um hash SHA-256
 * (evita que o código exponha os dados originais).
 */
export function generateValidationHash(): string {
  const raw = `${randomUUID()}-${Date.now()}`;
  const hash = createHash("sha256").update(raw).digest("hex");
  return hash.substring(0, 10).toUpperCase();
}
