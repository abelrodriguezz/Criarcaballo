"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { IconoPerfil } from "@/components/ui/Iconos";
import { CEDULA_VALIDA, useCampoCedula } from "@/lib/useCampoCedula";
import type { Diccionario } from "@/lib/i18n";

// Permisivo a propósito: solo descarta basura obvia, no intenta validar
// formatos internacionales de verdad (hay demasiados). Acepta dígitos,
// espacios y los símbolos comunes en números de teléfono.
const TELEFONO_VALIDO = /^[0-9+\-\s()]{6,30}$/;

export function DatosContactoForm({
  usuarioId,
  nombreActual,
  apellidoActual,
  cedulaActual,
  telefonoActual,
  t,
}: {
  usuarioId: string;
  nombreActual: string | null;
  apellidoActual: string | null;
  cedulaActual: string | null;
  telefonoActual: string | null;
  t: Diccionario;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [nombre, setNombre] = useState(nombreActual ?? "");
  const [apellido, setApellido] = useState(apellidoActual ?? "");
  // Mismo autoformato (y mismo manejo del cursor/Backspace sobre guiones)
  // que el registro.
  const {
    cedula,
    setCedula,
    inputRef: inputCedula,
    alCambiarCedula,
  } = useCampoCedula(cedulaActual ?? "");
  const [telefono, setTelefono] = useState(telefonoActual ?? "");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const nombreLimpio = nombre.trim();
    const apellidoLimpio = apellido.trim();
    const cedulaLimpia = cedula.trim();
    const telefonoLimpio = telefono.trim();

    // Mismo orden y mensajes que el registro (RegistroForm.tsx) — los 4
    // campos son obligatorios tanto al crear la cuenta como al editarla
    // (pedido del dueño, 2026-10-12).
    if (!nombreLimpio) {
      setError(t.auth.nombreRequerido);
      return;
    }
    if (!apellidoLimpio) {
      setError(t.auth.apellidoRequerido);
      return;
    }
    if (!cedulaLimpia) {
      setError(t.auth.cedulaRequerido);
      return;
    }
    if (!CEDULA_VALIDA.test(cedulaLimpia)) {
      setError(t.datosContacto.cedulaFormatoInvalido);
      return;
    }
    if (!telefonoLimpio) {
      setError(t.auth.telefonoRequerido);
      return;
    }
    if (!TELEFONO_VALIDO.test(telefonoLimpio)) {
      setError(t.datosContacto.formatoInvalido);
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("usuarios")
      .update({
        nombre: nombreLimpio,
        apellido: apellidoLimpio,
        cedula: cedulaLimpia,
        telefono: telefonoLimpio,
      })
      .eq("id", usuarioId);
    setGuardando(false);

    if (error) {
      // Migración 076: la cuenta pudo desactivarse con /perfil ya abierto.
      setError(
        error.message?.includes("desactivada")
          ? t.errores.cuentaDesactivadaAccion
          : t.wallet.errorGuardar
      );
      return;
    }

    setEditando(false);
    router.refresh();
  }

  if (!editando) {
    const resumen = [
      [nombreActual, apellidoActual].filter(Boolean).join(" "),
      telefonoActual,
    ]
      .filter(Boolean)
      .join(" · ");
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
      // noValidate: mismo motivo que RegistroForm.tsx -- sin esto, el
      // `required` nativo del navegador frena el envio con su propia
      // burbuja (en el idioma del navegador, no el de la app) antes de
      // llegar a manejarEnvio. required se deja igual por accesibilidad.
      noValidate
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-4"
    >
      <div className="flex justify-between items-center mb-2.5">
        <div className="font-medium text-sm">{t.datosContacto.titulo}</div>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setNombre(nombreActual ?? "");
            setApellido(apellidoActual ?? "");
            setCedula(cedulaActual ?? "");
            setTelefono(telefonoActual ?? "");
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          {t.wallet.cancelar}
        </button>
      </div>

      <div className="grid grid-cols-2 gap-1.5 mb-1.5">
        <input
          required
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
          placeholder={t.datosContacto.nombrePlaceholder}
          maxLength={100}
          className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <input
          required
          value={apellido}
          onChange={(e) => setApellido(e.target.value)}
          placeholder={t.datosContacto.apellidoPlaceholder}
          maxLength={100}
          className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
      </div>
      <input
        required
        ref={inputCedula}
        value={cedula}
        onChange={alCambiarCedula}
        placeholder={t.datosContacto.cedulaPlaceholder}
        inputMode="numeric"
        maxLength={13}
        className="w-full px-3.5 py-2.5 mb-1.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <input
        required
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
