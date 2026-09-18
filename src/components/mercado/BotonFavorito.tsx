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
  const [pendiente, iniciarTransicion] = useTransition();

  function alternar() {
    const nuevoEstado = !esFavorito;
    setEsFavorito(nuevoEstado); // optimista: se ve instantáneo

    const formData = new FormData();
    formData.set("activo", activo);

    iniciarTransicion(async () => {
      try {
        if (nuevoEstado) {
          await agregarFavorito(formData);
        } else {
          await quitarFavorito(formData);
        }
      } catch {
        setEsFavorito(!nuevoEstado); // revierte si falló
      }
    });
  }

  return (
    <button
      onClick={alternar}
      disabled={pendiente}
      aria-label={esFavorito ? "Quitar de favoritos" : "Agregar a favoritos"}
      aria-pressed={esFavorito}
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
  );
}
