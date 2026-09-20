"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { ConfigHero } from "@/lib/config-portada";

export function AdminPortadaForm({ heroActual }: { heroActual: ConfigHero }) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [hero, setHero] = useState(heroActual);
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setGuardando(true);

    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("config_portada")
      .upsert({ clave: "hero", valor: hero }, { onConflict: "clave" });

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
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-8 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        ✎ Editar textos de la portada (admin)
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-8"
    >
      <div className="flex justify-between items-center mb-4">
        <h3 className="font-display font-semibold text-sm">
          Editar textos de la portada
        </h3>
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        Badge superior
      </label>
      <input
        value={hero.badge}
        onChange={(e) => setHero({ ...hero, badge: e.target.value })}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <div className="grid grid-cols-2 gap-2.5 mb-2.5">
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1">
            Título — línea 1
          </label>
          <input
            value={hero.titulo_linea1}
            onChange={(e) =>
              setHero({ ...hero, titulo_linea1: e.target.value })
            }
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1">
            Título — línea 2
          </label>
          <input
            value={hero.titulo_linea2}
            onChange={(e) =>
              setHero({ ...hero, titulo_linea2: e.target.value })
            }
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        Subtítulo
      </label>
      <textarea
        value={hero.subtitulo}
        onChange={(e) => setHero({ ...hero, subtitulo: e.target.value })}
        rows={2}
        className="w-full px-3 py-2 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
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
