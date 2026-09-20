"use client";

import { useEffect } from "react";

/**
 * En Next.js 16 el prop para recuperarse de un error es `retry()`, no el
 * viejo `reset()`. La diferencia importa aquí: `reset()` solo limpia el
 * estado del error y vuelve a renderizar SIN volver a pedir los datos al
 * servidor, así que en un error de Server Component (que es de lo que
 * vive esta app: Supabase, Binance, Yahoo) el botón "Reintentar" fallaba
 * otra vez al instante. `retry()` sí vuelve a pedir y re-renderizar.
 * Ver node_modules/next/dist/docs/01-app/03-api-reference/03-file-conventions/error.md
 */
export default function ErrorGlobal({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
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
          onClick={() => retry()}
          className="bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          Reintentar
        </button>
      </div>
    </div>
  );
}
