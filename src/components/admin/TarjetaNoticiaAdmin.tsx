"use client";

import { useState } from "react";
import { AdminNoticiaForm } from "@/components/admin/AdminNoticiaForm";
import { BotonEliminarAdmin } from "@/components/admin/BotonEliminarAdmin";
import { urlSeguraParaEnlace } from "@/lib/url";
import type { Noticia } from "@/lib/types";

export function TarjetaNoticiaAdmin({
  noticia,
  esAdmin,
}: {
  noticia: Noticia;
  esAdmin: boolean;
}) {
  const [editando, setEditando] = useState(false);
  // Aunque la base ya solo acepta http/https (constraint
  // noticias_url_fuente_http, migración 021), esto cubre las filas que
  // pudieran venir de antes y cualquier otra vía de escritura futura.
  const urlFuente = urlSeguraParaEnlace(noticia.url_fuente);

  if (editando) {
    return (
      <AdminNoticiaForm
        noticiaExistente={noticia}
        onCancelar={() => setEditando(false)}
      />
    );
  }

  return (
    <article className="border border-[var(--border)] rounded-2xl p-5">
      <div className="flex items-start justify-between gap-3 mb-1.5">
        <h2 className="font-display font-semibold text-base">
          {noticia.titulo}
        </h2>
        {noticia.destacada && (
          <span className="bg-brand-secondary/15 text-brand-secondary text-xs font-bold px-2.5 py-1 rounded-full whitespace-nowrap">
            Destacada
          </span>
        )}
      </div>
      {noticia.resumen && (
        <p className="text-sm text-foreground-muted mb-2">
          {noticia.resumen}
        </p>
      )}
      {urlFuente && (
        <a
          href={urlFuente}
          target="_blank"
          rel="noopener noreferrer"
          className="text-brand-primary text-[13px] font-semibold"
        >
          Ver fuente →
        </a>
      )}
      {esAdmin && (
        <div className="flex gap-3 mt-2.5">
          <button
            onClick={() => setEditando(true)}
            className="text-xs font-semibold text-brand-primary hover:underline"
          >
            Editar
          </button>
          <BotonEliminarAdmin
            tabla="noticias"
            id={noticia.id}
            textoConfirmacion={`¿Eliminar la noticia "${noticia.titulo}"?`}
          />
        </div>
      )}
    </article>
  );
}
