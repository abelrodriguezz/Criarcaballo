"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { TextosAdmin } from "@/lib/i18n";
import type { ConfigNosotrosAmbosIdiomas } from "@/lib/config-nosotros";

export function AdminNosotrosForm({
  nosotrosActual,
  ta,
}: {
  nosotrosActual: ConfigNosotrosAmbosIdiomas;
  ta: TextosAdmin;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [nosotros, setNosotros] = useState(nosotrosActual);
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
      .upsert({ clave: "nosotros", valor: nosotros }, { onConflict: "clave" });

    setGuardando(false);

    if (error) {
      setError(ta.errorPermiso);
      return;
    }

    setAbierto(false);
    router.refresh();
  }

  // Cancelar descarta lo editado: sin esto, el estado local sobrevivía al
  // cerrar el form, al reabrirlo aparecían los cambios "cancelados" y un
  // "Guardar" posterior los publicaba. nosotrosActual viene del servidor y
  // se actualiza con router.refresh() tras cada guardado.
  function cancelar() {
    setNosotros(nosotrosActual);
    setIdioma("es");
    setError(null);
    setAbierto(false);
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-8 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        {ta.nosotrosEditarBoton}
      </button>
    );
  }

  // El título y los párrafos cambian de campo según el idioma que se esté
  // editando (titulo vs titulo_en, parrafos vs parrafos_en) — agregar o
  // eliminar un párrafo afecta AMBOS idiomas a la vez (misma posición =
  // mismo tema en los dos idiomas), aunque solo se esté viendo uno.
  const titulo = idioma === "en" ? nosotros.titulo_en : nosotros.titulo;
  const parrafos = idioma === "en" ? nosotros.parrafos_en : nosotros.parrafos;

  function cambiarTitulo(valor: string) {
    setNosotros((n) => ({
      ...n,
      [idioma === "en" ? "titulo_en" : "titulo"]: valor,
    }));
  }

  function cambiarParrafo(indice: number, valor: string) {
    setNosotros((n) => {
      const campo = idioma === "en" ? "parrafos_en" : "parrafos";
      const nuevos = [...n[campo]];
      nuevos[indice] = valor;
      return { ...n, [campo]: nuevos };
    });
  }

  function agregarParrafo() {
    setNosotros((n) => ({
      ...n,
      parrafos: [...n.parrafos, ""],
      parrafos_en: [...n.parrafos_en, ""],
    }));
  }

  function eliminarParrafo(indice: number) {
    setNosotros((n) => ({
      ...n,
      parrafos: n.parrafos.filter((_, i) => i !== indice),
      parrafos_en: n.parrafos_en.filter((_, i) => i !== indice),
    }));
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-8"
    >
      <div className="flex justify-between items-center mb-4">
        <h3 className="font-display font-semibold text-sm">
          {ta.nosotrosEditarTitulo}
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
        {ta.parrafos}
      </label>
      <div className="flex flex-col gap-2 mb-2.5">
        {parrafos.map((p, i) => (
          <div key={i} className="flex gap-2 items-start">
            <textarea
              value={p}
              onChange={(e) => cambiarParrafo(i, e.target.value)}
              rows={3}
              className="flex-1 px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
            />
            <button
              type="button"
              onClick={() => eliminarParrafo(i)}
              className="text-loss text-xs font-semibold px-2 py-2 shrink-0"
            >
              {ta.eliminar}
            </button>
          </div>
        ))}
        {parrafos.length === 0 && (
          <p className="text-[12px] text-foreground-muted italic">
            {ta.sinParrafos}
          </p>
        )}
      </div>

      <button
        type="button"
        onClick={agregarParrafo}
        className="text-brand-primary text-xs font-semibold mb-4"
      >
        {ta.agregarParrafo}
      </button>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <div>
        <button
          type="submit"
          disabled={guardando}
          className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          {guardando ? ta.guardando : ta.guardarCambios}
        </button>
      </div>
    </form>
  );
}
