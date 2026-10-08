"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { TextosAdmin } from "@/lib/i18n";
import type { TextosModuloAmbosIdiomas } from "@/lib/config-textos-modulo";

/** Reusado en Trade del día, Comunidad, Señales y Mercado — mismo patrón visual que AdminNosotrosForm. */
export function AdminTextosModuloForm({
  claveConfig,
  textosActuales,
  ta,
}: {
  claveConfig: string;
  textosActuales: TextosModuloAmbosIdiomas;
  ta: TextosAdmin;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [textos, setTextos] = useState(textosActuales);
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
      .upsert({ clave: claveConfig, valor: textos }, { onConflict: "clave" });

    setGuardando(false);

    if (error) {
      setError(ta.errorPermiso);
      return;
    }

    setAbierto(false);
    router.refresh();
  }

  // Cancelar descarta lo editado — mismo motivo que AdminNosotrosForm.
  function cancelar() {
    setTextos(textosActuales);
    setIdioma("es");
    setError(null);
    setAbierto(false);
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        {ta.editarTextosBoton}
      </button>
    );
  }

  const titulo = idioma === "en" ? textos.titulo_en : textos.titulo;
  const subtitulo = idioma === "en" ? textos.subtitulo_en : textos.subtitulo;

  function cambiarTitulo(valor: string) {
    setTextos((t) => ({ ...t, [idioma === "en" ? "titulo_en" : "titulo"]: valor }));
  }

  function cambiarSubtitulo(valor: string) {
    setTextos((t) => ({
      ...t,
      [idioma === "en" ? "subtitulo_en" : "subtitulo"]: valor,
    }));
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-6"
    >
      <div className="flex justify-between items-center mb-4">
        <h3 className="font-display font-semibold text-sm">
          {ta.editarTextosTitulo}
        </h3>
        <button
          type="button"
          onClick={cancelar}
          className="text-xs text-foreground-muted"
        >
          {ta.cancelar}
        </button>
      </div>

      <div className="flex items-center border border-[var(--border)] w-fit mb-4 text-[11px] font-bold">
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

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        {ta.titulo}
      </label>
      <input
        value={titulo}
        onChange={(e) => cambiarTitulo(e.target.value)}
        className="w-full px-3 py-2 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <label className="block text-[12px] font-medium text-foreground-muted mb-1">
        {ta.subtitulo}
      </label>
      <textarea
        value={subtitulo}
        onChange={(e) => cambiarSubtitulo(e.target.value)}
        rows={2}
        className="w-full px-3 py-2 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? ta.guardando : ta.guardarCambios}
      </button>
    </form>
  );
}
