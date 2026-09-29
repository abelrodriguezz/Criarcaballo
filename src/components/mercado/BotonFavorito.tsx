"use client";

import { useState, useTransition } from "react";
import { agregarFavorito, quitarFavorito } from "@/lib/actions/favoritos";
import { IconoEstrella } from "@/components/ui/Iconos";

export function BotonFavorito({
  activo,
  esFavoritoInicial,
}: {
  activo: string;
  esFavoritoInicial: boolean;
}) {
  const [esFavorito, setEsFavorito] = useState(esFavoritoInicial);
  const [error, setError] = useState<string | null>(null);

  // Un mismo activo puede aparecer en dos tarjetas de /mercado a la vez
  // (p. ej. HBARUSDT en "Lo que más subió hoy" y en "Cripto"). Al marcar una
  // estrella, la Server Action revalida la página y llega el valor nuevo
  // por props, pero useState ignoraba ese cambio: la otra estrella seguía
  // mostrando el estado viejo hasta recargar. Se sincroniza cuando el valor
  // del servidor cambia (patrón "ajustar estado durante el render").
  const [inicialPrevio, setInicialPrevio] = useState(esFavoritoInicial);
  if (inicialPrevio !== esFavoritoInicial) {
    setInicialPrevio(esFavoritoInicial);
    setEsFavorito(esFavoritoInicial);
  }
  const [pendiente, iniciarTransicion] = useTransition();

  function alternar() {
    const nuevoEstado = !esFavorito;
    setError(null);
    setEsFavorito(nuevoEstado); // optimista: se ve instantáneo

    const formData = new FormData();
    formData.set("activo", activo);

    iniciarTransicion(async () => {
      try {
        const resultado = nuevoEstado
          ? await agregarFavorito(formData)
          : await quitarFavorito(formData);

        if (!resultado.ok) {
          // Antes la estrella simplemente se revertía sin decir nada, así
          // que quien llegaba al tope de 50 favoritos (trigger de la
          // migración 021) veía la estrella "rebotar" sin ninguna
          // explicación y lo reintentaba una y otra vez.
          setEsFavorito(!nuevoEstado);
          setError(resultado.error);
        }
      } catch {
        setEsFavorito(!nuevoEstado);
        setError("No se pudo guardar el favorito. Inténtalo de nuevo.");
      }
    });
  }

  return (
    <span className="relative inline-flex">
      <button
        onClick={alternar}
        disabled={pendiente}
        aria-label={esFavorito ? "Quitar de favoritos" : "Agregar a favoritos"}
        aria-pressed={esFavorito}
        title={error ?? undefined}
        className="disabled:opacity-50 transition-colors"
      >
        <IconoEstrella
          className={`w-4 h-4 ${
            esFavorito
              ? "text-brand-secondary fill-brand-secondary"
              : "text-foreground-muted"
          }`}
        />
      </button>
      {error && (
        <span
          role="alert"
          onClick={() => setError(null)}
          className="absolute left-0 top-full mt-1 z-20 w-max max-w-[240px] cursor-pointer rounded-lg border border-[var(--border)] bg-background px-2.5 py-1.5 text-[11px] leading-snug text-loss shadow-lg"
        >
          {error}
        </span>
      )}
    </span>
  );
}
