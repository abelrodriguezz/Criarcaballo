import Link from "next/link";

export default function NoEncontrado() {
  return (
    <div className="py-16 flex flex-col items-center text-center">
      <div className="border border-dashed border-[var(--border)] rounded-2xl p-8 max-w-[420px]">
        <h1 className="font-display font-semibold text-lg mb-2">
          Página no encontrada
        </h1>
        <p className="text-foreground-muted text-sm mb-5">
          El enlace que seguiste no existe o ya no está disponible.
        </p>
        <Link
          href="/"
          className="inline-block bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          Volver al inicio
        </Link>
      </div>
    </div>
  );
}
