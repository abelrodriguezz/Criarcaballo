"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { ConfigHorarioMercado } from "@/lib/config-horario-mercado";

// Mismo patrón visual que AdminSimulacionForm/AdminPickForm — pantalla solo
// de admin, textos fijos en español a propósito (decisión del usuario,
// 2026-09-27).
const DIAS: { valor: number; etiqueta: string }[] = [
  { valor: 1, etiqueta: "Lun" },
  { valor: 2, etiqueta: "Mar" },
  { valor: 3, etiqueta: "Mié" },
  { valor: 4, etiqueta: "Jue" },
  { valor: 5, etiqueta: "Vie" },
  { valor: 6, etiqueta: "Sáb" },
  { valor: 7, etiqueta: "Dom" },
];

export function AdminHorarioMercadoForm({
  horarioActual,
}: {
  horarioActual: ConfigHorarioMercado;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [horario, setHorario] = useState(horarioActual);
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  function alternarDia(dia: number) {
    setHorario((h) => ({
      ...h,
      dias: h.dias.includes(dia)
        ? h.dias.filter((d) => d !== dia)
        : [...h.dias, dia].sort(),
    }));
  }

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!horario.abierto_siempre && horario.dias.length === 0) {
      setError("Marca al menos un día habilitado, o activa \"cualquier momento\".");
      return;
    }
    if (!horario.abierto_siempre && horario.apertura >= horario.cierre) {
      setError("La hora de apertura debe ser antes que la de cierre.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error: dbError } = await supabase
      .from("config_portada")
      .upsert({ clave: "horario_mercado", valor: horario }, { onConflict: "clave" });

    setGuardando(false);

    if (dbError) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    setAbierto(false);
    router.refresh();
  }

  if (!abierto) {
    const resumen = horarioActual.abierto_siempre
      ? "Cualquier momento (sin restricción)"
      : `${DIAS.filter((d) => horarioActual.dias.includes(d.valor))
          .map((d) => d.etiqueta)
          .join(", ")} · ${horarioActual.apertura} a ${horarioActual.cierre} (hora NY)`;

    return (
      <button
        onClick={() => {
          setHorario(horarioActual);
          setAbierto(true);
        }}
        className="w-full text-left border border-dashed border-[var(--brand-primary)] text-sm px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        <span className="text-brand-primary font-semibold">
          ✎ Horario de mercado (admin):
        </span>{" "}
        <span className="text-foreground-muted">{resumen}</span>
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-6"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">Horario de mercado</h3>
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>
      <p className="text-[12px] text-foreground-muted mb-3">
        Controla cuándo los usuarios normales pueden abrir operaciones (el
        admin siempre puede, sin importar esto). Los días y horas se
        interpretan en hora de Nueva York.
      </p>

      <label className="flex items-center gap-2 mb-3 text-sm">
        <input
          type="checkbox"
          checked={horario.abierto_siempre}
          onChange={(e) =>
            setHorario((h) => ({ ...h, abierto_siempre: e.target.checked }))
          }
        />
        Permitir operar en cualquier momento (ignorar días y horario — para
        que los usuarios simulen a cualquier hora)
      </label>

      {!horario.abierto_siempre && (
        <>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
            Días habilitados
          </label>
          <div className="flex gap-1.5 mb-3">
            {DIAS.map(({ valor, etiqueta }) => (
              <button
                key={valor}
                type="button"
                onClick={() => alternarDia(valor)}
                className={`px-2.5 py-1.5 rounded-lg text-[12px] font-semibold border transition-colors ${
                  horario.dias.includes(valor)
                    ? "bg-brand-primary/15 border-brand-primary text-brand-primary"
                    : "border-[var(--border)] text-foreground-muted"
                }`}
              >
                {etiqueta}
              </button>
            ))}
          </div>

          <div className="flex gap-3 mb-3">
            <div className="flex-1">
              <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                Hora de apertura (NY)
              </label>
              <input
                type="time"
                value={horario.apertura}
                onChange={(e) =>
                  setHorario((h) => ({ ...h, apertura: e.target.value }))
                }
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
              />
            </div>
            <div className="flex-1">
              <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                Hora de cierre (NY)
              </label>
              <input
                type="time"
                value={horario.cierre}
                onChange={(e) =>
                  setHorario((h) => ({ ...h, cierre: e.target.value }))
                }
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
              />
            </div>
          </div>
        </>
      )}

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
