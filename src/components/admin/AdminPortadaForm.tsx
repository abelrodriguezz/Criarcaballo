"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { ConfigHeroAmbosIdiomas } from "@/lib/config-portada";

export function AdminPortadaForm({
  heroActual,
}: {
  heroActual: ConfigHeroAmbosIdiomas;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [hero, setHero] = useState(heroActual);
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

  // Los nombres de campo cambian según el idioma que se esté editando
  // (badge vs badge_en, etc.) — la portada pública lee el que corresponda
  // según el idioma que la persona haya elegido con el toggle ES/EN.
  const sufijo = idioma === "en" ? "_en" : "";
  const badge = idioma === "en" ? hero.badge_en : hero.badge;
  const titulo1 = idioma === "en" ? hero.titulo_linea1_en : hero.titulo_linea1;
  const titulo2 = idioma === "en" ? hero.titulo_linea2_en : hero.titulo_linea2;
  const subtitulo = idioma === "en" ? hero.subtitulo_en : hero.subtitulo;

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

      <div className="flex items-center border border-[var(--border)] w-fit mb-4 text-[11px] font-bold">
        <button
          type="button"
          onClick={() => setIdioma("es")}
          className={`px-3 py-1.5 transition-colors ${
            idioma === "es"
              ? "bg-brand-primary text-white"
              : "text-foreground-muted"
          }`}
        >
          Español
        </button>
        <button
          type="button"
          onClick={() => setIdioma("en")}
          className={`px-3 py-1.5 transition-colors ${
            idioma === "en"
              ? "bg-brand-primary text-white"
              : "text-foreground-muted"
          }`}
        >
          English
        </button>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        Badge superior
      </label>
      <input
        value={badge}
        onChange={(e) =>
          setHero({ ...hero, [`badge${sufijo}`]: e.target.value })
        }
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <div className="grid grid-cols-2 gap-2.5 mb-2.5">
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1">
            Título — línea 1
          </label>
          <input
            value={titulo1}
            onChange={(e) =>
              setHero({ ...hero, [`titulo_linea1${sufijo}`]: e.target.value })
            }
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1">
            Título — línea 2
          </label>
          <input
            value={titulo2}
            onChange={(e) =>
              setHero({ ...hero, [`titulo_linea2${sufijo}`]: e.target.value })
            }
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        Subtítulo
      </label>
      <textarea
        value={subtitulo}
        onChange={(e) =>
          setHero({ ...hero, [`subtitulo${sufijo}`]: e.target.value })
        }
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
