"use client";

import { useState, FormEvent } from "react";

type ValidationResult = {
  valid: boolean;
  status?: string;
  hash?: string;
  issuedAt?: string;
  participantName?: string;
  participantEmail?: string;
  event?: { title?: string; workloadHours?: number; instructor?: string };
  downloadUrl?: string | null;
  message?: string;
};

export default function ValidarPage() {
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<ValidationResult | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setResult(null);
    try {
      const res = await fetch(`/api/validate?hash=${encodeURIComponent(query.trim())}`);
      const data = await res.json();
      setResult(data);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen flex flex-col items-center justify-center px-6 py-16">
      <div className="w-full max-w-md">
        <p className="font-mono text-xs tracking-[0.3em] text-accent uppercase mb-2">
          Autenticidade
        </p>
        <h1 className="text-3xl font-semibold mb-2">Valide um certificado</h1>
        <p className="text-muted text-sm mb-8">
          Digite o código impresso no certificado (ex: A9X3G7K9A1) ou escaneie o QR Code do documento.
        </p>

        <form onSubmit={handleSubmit} className="flex gap-2">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Código de validação"
            className="flex-1 bg-surface border border-white/10 rounded-md px-4 py-3 font-mono text-sm outline-none focus:border-accent transition-colors"
          />
          <button
            type="submit"
            disabled={loading}
            className="bg-accent text-background font-medium px-5 rounded-md hover:opacity-90 transition-opacity disabled:opacity-50"
          >
            {loading ? "..." : "Validar"}
          </button>
        </form>

        {result && (
          <div className="mt-8 rounded-lg border border-white/10 bg-surface p-6">
            {result.valid ? (
              <>
                <div className="flex items-center gap-2 mb-4">
                  <span className="h-2 w-2 rounded-full bg-accent" />
                  <span className="text-accent text-sm font-medium">Certificado válido</span>
                </div>
                <dl className="space-y-3 text-sm">
                  <div>
                    <dt className="text-muted">Participante</dt>
                    <dd>{result.participantName}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">Curso</dt>
                    <dd>{result.event?.title}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">Carga horária</dt>
                    <dd>{result.event?.workloadHours}h</dd>
                  </div>
                  <div>
                    <dt className="text-muted">Emitido em</dt>
                    <dd>
                      {result.issuedAt
                        ? new Date(result.issuedAt).toLocaleDateString("pt-BR")
                        : "—"}
                    </dd>
                  </div>
                </dl>
                {result.downloadUrl && (
                  <a
                    href={result.downloadUrl}
                    target="_blank"
                    className="mt-5 inline-block text-accent text-sm underline underline-offset-4"
                  >
                    Baixar cópia em PDF
                  </a>
                )}
              </>
            ) : (
              <p className="text-sm text-red-400">
                {result.message ?? "Código não encontrado ou certificado revogado."}
              </p>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
