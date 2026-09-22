"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { IconoPerfil } from "@/components/ui/Iconos";
import type { Diccionario } from "@/lib/i18n";

// Permisivo a propósito: solo descarta basura obvia, no intenta validar
// formatos internacionales de verdad (hay demasiados). Acepta dígitos,
// espacios y los símbolos comunes en números de teléfono.
const TELEFONO_VALIDO = /^[0-9+\-\s()]{6,30}$/;

export function DatosContactoForm({
  usuarioId,
  nombreActual,
  telefonoActual,
  t,
}: {
  usuarioId: string;
  nombreActual: string | null;
  telefonoActual: string | null;
  t: Diccionario;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [nombre, setNombre] = useState(nombreActual ?? "");
  const [telefono, setTelefono] = useState(telefonoActual ?? "");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const nombreLimpio = nombre.trim();
    const telefonoLimpio = telefono.trim();

    if (telefonoLimpio && !TELEFONO_VALIDO.test(telefonoLimpio)) {
      setError(t.datosContacto.formatoInvalido);
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("usuarios")
      .update({
        nombre: nombreLimpio || null,
        telefono: telefonoLimpio || null,
      })
      .eq("id", usuarioId);
    setGuardando(false);

    if (error) {
      setError(t.wallet.errorGuardar);
      return;
    }

    setEditando(false);
    router.refresh();
  }

  if (!editando) {
    const resumen = [nombreActual, telefonoActual].filter(Boolean).join(" · ");
    return (
      <button
        onClick={() => setEditando(true)}
        className="w-full text-left border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5 hover:bg-surface-hover hover:border-brand-primary/40 transition-colors"
      >
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-brand-primary/10 text-brand-primary flex items-center justify-center">
          <IconoPerfil />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.datosContacto.titulo}</div>
          <div className="text-[13px] text-foreground-muted truncate">
            {resumen || t.datosContacto.sinDatos}
          </div>
        </div>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="w-4 h-4 shrink-0 text-foreground-muted"
        >
          <polyline points="9 18 15 12 9 6" />
        </svg>
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-4"
    >
      <div className="flex justify-between items-center mb-2.5">
        <div className="font-medium text-sm">{t.datosContacto.titulo}</div>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setNombre(nombreActual ?? "");
            setTelefono(telefonoActual ?? "");
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          {t.wallet.cancelar}
        </button>
      </div>

      <input
        value={nombre}
        onChange={(e) => setNombre(e.target.value)}
        placeholder={t.datosContacto.nombrePlaceholder}
        maxLength={100}
        className="w-full px-3.5 py-2.5 mb-1.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <input
        value={telefono}
        onChange={(e) => setTelefono(e.target.value)}
        placeholder={t.datosContacto.telefonoPlaceholder}
        maxLength={30}
        className="w-full px-3.5 py-2.5 mb-1.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <p className="text-[12px] text-foreground-muted mb-3">
        {t.datosContacto.descripcion}
      </p>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? t.wallet.guardando : t.wallet.guardar}
      </button>
    </form>
  );
}
