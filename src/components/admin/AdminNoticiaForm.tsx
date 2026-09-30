"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { urlSeguraParaEnlace } from "@/lib/url";
import { es } from "@/lib/i18n/diccionarios/es";
import { rellenar, type TextosAdmin } from "@/lib/i18n";
import type { Noticia } from "@/lib/types";

interface AdminNoticiaFormProps {
  noticiaExistente?: Noticia;
  onCancelar?: () => void;
  ta?: TextosAdmin;
}

export function AdminNoticiaForm({
  noticiaExistente,
  onCancelar,
  ta = es.admin,
}: AdminNoticiaFormProps) {
  const router = useRouter();
  const esEdicion = !!noticiaExistente;

  const [titulo, setTitulo] = useState(noticiaExistente?.titulo ?? "");
  const [tituloEn, setTituloEn] = useState(noticiaExistente?.titulo_en ?? "");
  const [resumen, setResumen] = useState(noticiaExistente?.resumen ?? "");
  const [resumenEn, setResumenEn] = useState(noticiaExistente?.resumen_en ?? "");
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
      setError(ta.errTituloVacio);
      return;
    }

    // La URL termina como href en la portada pública: solo http/https.
    // La base también lo exige (constraint noticias_url_fuente_http), pero
    // aquí el mensaje es entendible en vez de un error de Postgres.
    const urlLimpia = urlFuente?.trim() ? urlSeguraParaEnlace(urlFuente) : null;
    if (urlFuente?.trim() && !urlLimpia) {
      setError(ta.errUrl);
      return;
    }

    setGuardando(true);

    const supabase = crearClienteSupabase();
    const datos = {
      titulo: titulo.trim(),
      titulo_en: tituloEn.trim() || null,
      resumen: resumen || null,
      resumen_en: resumenEn || null,
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
      setError(ta.errorPermiso);
      return;
    }

    if (esEdicion) {
      onCancelar?.();
    } else {
      setTitulo("");
      setTituloEn("");
      setResumen("");
      setResumenEn("");
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
        {ta.publicarNoticiaBoton}
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
          {esEdicion ? ta.editarNoticia : ta.publicarNoticia}
        </h3>
        <button
          type="button"
          onClick={cerrar}
          className="text-xs text-foreground-muted"
        >
          {ta.cancelar}
        </button>
      </div>

      <input
        required
        value={titulo}
        onChange={(e) => setTitulo(e.target.value)}
        aria-label={ta.noticiaTitulo}
        placeholder={ta.noticiaTitulo}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <textarea
        value={resumen ?? ""}
        onChange={(e) => setResumen(e.target.value)}
        aria-label={ta.noticiaResumen}
        placeholder={ta.noticiaResumen}
        rows={2}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />
      <input
        value={tituloEn}
        onChange={(e) => setTituloEn(e.target.value)}
        aria-label={ta.noticiaTituloEn}
        placeholder={ta.noticiaTituloEn}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <textarea
        value={resumenEn ?? ""}
        onChange={(e) => setResumenEn(e.target.value)}
        aria-label={ta.noticiaResumenEn}
        placeholder={ta.noticiaResumenEn}
        rows={2}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />
      <input
        value={urlFuente ?? ""}
        onChange={(e) => setUrlFuente(e.target.value)}
        aria-label={ta.noticiaUrl}
        placeholder={ta.noticiaUrl}
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <label className="flex items-center gap-2 text-sm mb-3">
        <input
          type="checkbox"
          checked={destacada}
          onChange={(e) => setDestacada(e.target.checked)}
        />
        {ta.destacarPortada}
      </label>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? ta.guardando : esEdicion ? ta.guardarCambios : ta.publicar}
      </button>
    </form>
  );
}
