"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { ConfigSimulacionAmbosIdiomas } from "@/lib/config-simulacion";

export function AdminSimulacionForm({
  simulacionActual,
}: {
  simulacionActual: ConfigSimulacionAmbosIdiomas;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [simulacion, setSimulacion] = useState(simulacionActual);
  const [idioma, setIdioma] = useState<"es" | "en">("es");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setGuardando(true);

    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("config_portada")
      .upsert(
        { clave: "simulacion_deposito", valor: simulacion },
        { onConflict: "clave" }
      );

    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    setAbierto(false);
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-3 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        ✎ Editar mensaje de simulación (admin)
      </button>
    );
  }

  const mensaje = idioma === "en" ? simulacion.mensaje_en : simulacion.mensaje;

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-3"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">
          Mensaje de simulación
        </h3>
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>
      <p className="text-[12px] text-foreground-muted mb-3">
        Este mismo mensaje se reutiliza en cualquier botón de
        &quot;simulación&quot; de la app (hoy solo el de &quot;Depositar&quot;).
      </p>

      <div className="flex items-center border border-[var(--border)] w-fit mb-3 text-[11px] font-bold">
        <button
          type="button"
          onClick={() => setIdioma("es")}
          className={`px-3 py-1.5 transition-colors ${
            idioma === "es" ? "bg-brand-primary text-white" : "text-foreground-muted"
          }`}
        >
          Español
        </button>
        <button
          type="button"
          onClick={() => setIdioma("en")}
          className={`px-3 py-1.5 transition-colors ${
            idioma === "en" ? "bg-brand-primary text-white" : "text-foreground-muted"
          }`}
        >
          English
        </button>
      </div>

      <textarea
        value={mensaje}
        onChange={(e) =>
          setSimulacion((s) => ({
            ...s,
            [idioma === "en" ? "mensaje_en" : "mensaje"]: e.target.value,
          }))
        }
        rows={3}
        className="w-full px-3 py-2 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : "Guardar cambios"}
      </button>
    </form>
  );
}
