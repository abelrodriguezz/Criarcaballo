"use client";

import { useEffect } from "react";

export default function ErrorGlobal({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="py-16 flex flex-col items-center text-center">
      <div className="border border-dashed border-[var(--border)] rounded-2xl p-8 max-w-[420px]">
        <h1 className="font-display font-semibold text-lg mb-2">
          Algo salió mal
        </h1>
        <p className="text-foreground-muted text-sm mb-5">
          No pudimos cargar esta página. Puede ser un problema temporal de
          conexión — intenta de nuevo en un momento.
        </p>
        <button
          onClick={reset}
          className="bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          Reintentar
        </button>
      </div>
    </div>
  );
}
