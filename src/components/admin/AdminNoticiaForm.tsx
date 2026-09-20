"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { urlSeguraParaEnlace } from "@/lib/url";
import type { Noticia } from "@/lib/types";

interface AdminNoticiaFormProps {
  noticiaExistente?: Noticia;
  onCancelar?: () => void;
}

export function AdminNoticiaForm({
  noticiaExistente,
  onCancelar,
}: AdminNoticiaFormProps) {
  const router = useRouter();
  const esEdicion = !!noticiaExistente;

  const [titulo, setTitulo] = useState(noticiaExistente?.titulo ?? "");
  const [resumen, setResumen] = useState(noticiaExistente?.resumen ?? "");
  const [urlFuente, setUrlFuente] = useState(
    noticiaExistente?.url_fuente ?? ""
  );
  const [destacada, setDestacada] = useState(
    noticiaExistente?.destacada ?? false
  );
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(esEdicion);

  function cerrar() {
    setAbierto(false);
    onCancelar?.();
  }

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!titulo.trim()) {
      setError("El título no puede estar vacío.");
      return;
    }

    // La URL termina como href en la portada pública: solo http/https.
    // La base también lo exige (constraint noticias_url_fuente_http), pero
    // aquí el mensaje es entendible en vez de un error de Postgres.
    const urlLimpia = urlFuente?.trim() ? urlSeguraParaEnlace(urlFuente) : null;
    if (urlFuente?.trim() && !urlLimpia) {
      setError(
        "La URL de la fuente tiene que ser un enlace http:// o https:// válido."
      );
      return;
    }

    setGuardando(true);

    const supabase = crearClienteSupabase();
    const datos = {
      titulo: titulo.trim(),
      resumen: resumen || null,
      url_fuente: urlLimpia,
      destacada,
    };

    const { error } = esEdicion
      ? await supabase
          .from("noticias")
          .update(datos)
          .eq("id", noticiaExistente.id)
      : await supabase.from("noticias").insert(datos);

    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    if (esEdicion) {
      onCancelar?.();
    } else {
      setTitulo("");
      setResumen("");
      setUrlFuente("");
      setDestacada(false);
      setAbierto(false);
    }
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        + Publicar noticia (admin)
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-6"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">
          {esEdicion ? "Editar noticia" : "Publicar noticia"}
        </h3>
        <button
          type="button"
          onClick={cerrar}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <input
        required
        value={titulo}
        onChange={(e) => setTitulo(e.target.value)}
        aria-label="Título"
        placeholder="Título"
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <textarea
        value={resumen ?? ""}
        onChange={(e) => setResumen(e.target.value)}
        aria-label="Resumen"
        placeholder="Resumen (opcional)"
        rows={2}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />
      <input
        value={urlFuente ?? ""}
        onChange={(e) => setUrlFuente(e.target.value)}
        aria-label="URL de la fuente"
        placeholder="URL de la fuente (opcional)"
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <label className="flex items-center gap-2 text-sm mb-3">
        <input
          type="checkbox"
          checked={destacada}
          onChange={(e) => setDestacada(e.target.checked)}
        />
        Destacar en portada
      </label>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : esEdicion ? "Guardar cambios" : "Publicar"}
      </button>
    </form>
  );
}
