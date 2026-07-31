export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center justify-center px-6 text-center">
      <p className="font-mono text-xs tracking-[0.3em] text-accent uppercase mb-3">
        Certifica Fácil
      </p>
      <h1 className="text-3xl font-semibold mb-4 max-w-lg">
        Emissão e validação de certificados para ligas acadêmicas
      </h1>
      <p className="text-muted text-sm max-w-md mb-8">
        Dashboard do organizador ainda em construção — comece explorando a página pública de validação.
      </p>
      <a
        href="/validar"
        className="bg-accent text-background font-medium px-5 py-3 rounded-md hover:opacity-90 transition-opacity"
      >
        Ir para validação pública
      </a>
    </main>
  );
}
