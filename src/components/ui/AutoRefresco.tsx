"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/**
 * Refresca la página (re-ejecuta el Server Component) cada cierto
 * intervalo, sin recargar el navegador. Se usa en /senales para que el
 * chequeo de TP/SL se repita mientras alguien tiene la pestaña abierta,
 * no solo cuando entra por primera vez.
 */
export function AutoRefresco({ intervaloMs = 45000 }: { intervaloMs?: number }) {
  const router = useRouter();

  useEffect(() => {
    const id = setInterval(() => router.refresh(), intervaloMs);
    return () => clearInterval(id);
  }, [router, intervaloMs]);

  return null;
}
