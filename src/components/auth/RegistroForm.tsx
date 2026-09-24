"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import { Turnstile } from "@/components/auth/Turnstile";
import type { Diccionario, Locale } from "@/lib/i18n";

// Ver nota en LoginForm.tsx: sin site key configurada, el captcha se omite
// en vez de dejar el formulario deshabilitado para siempre.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

// Duplicado a propósito de DatosContactoForm.tsx: es un regex autocontenido,
// sin dependencias, y así este formulario no gana un import extra.
const TELEFONO_VALIDO = /^[0-9+\-\s()]{6,30}$/;

export function RegistroForm({ t, locale }: { t: Diccionario; locale: Locale }) {
  const searchParams = useSearchParams();
  const codigoRefUrl = searchParams.get("ref");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmar, setConfirmar] = useState("");
  const [nombre, setNombre] = useState("");
  const [telefono, setTelefono] = useState("");
  const [codigoInvitacion, setCodigoInvitacion] = useState(codigoRefUrl ?? "");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exito, setExito] = useState(false);
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const nombreLimpio = nombre.trim();
    if (!nombreLimpio) {
      setError(t.auth.nombreRequerido);
      return;
    }
    const telefonoLimpio = telefono.trim();
    if (!telefonoLimpio) {
      setError(t.auth.telefonoRequerido);
      return;
    }
    if (!TELEFONO_VALIDO.test(telefonoLimpio)) {
      setError(t.datosContacto.formatoInvalido);
      return;
    }
    if (password !== confirmar) {
      setError(t.auth.contrasenasNoCoinciden);
      return;
    }
    if (password.length < 8) {
      setError(t.auth.contrasenaCorta);
      return;
    }
    if (TURNSTILE_CONFIGURADO && !captchaToken) {
      setError(t.auth.completaVerificacion);
      return;
    }

    // El código se guarda en mayúsculas (así se generan en la base de
    // datos) para que el trigger handle_new_user() lo encuentre sin
    // importar cómo lo haya escrito la persona.
    const codigoLimpio = codigoInvitacion.trim().toUpperCase();

    setCargando(true);
    const supabase = crearClienteSupabase();

    // invitado_por es inmutable una vez creada la cuenta (no se puede
    // corregir después), así que si escribieron algo, confirmamos que
    // exista ANTES de registrar — no después, cuando ya sería tarde.
    if (codigoLimpio) {
      const { data: codigoValido, error: errorCodigo } = await supabase.rpc(
        "codigo_invitacion_valido",
        { p_codigo: codigoLimpio }
      );
      if (errorCodigo) {
        setCargando(false);
        setError(t.auth.errorRegistroGenerico);
        return;
      }
      if (!codigoValido) {
        setCargando(false);
        setError(t.auth.codigoInvitacionInvalido);
        return;
      }
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        ...(captchaToken ? { captchaToken } : {}),
        data: {
          ...(codigoLimpio ? { ref: codigoLimpio } : {}),
          nombre: nombreLimpio,
          telefono: telefonoLimpio,
        },
      },
    });
    setCargando(false);

    if (error) {
      setError(mensajeErrorAuth(error, t.auth.errorRegistroGenerico, locale));
      setCaptchaToken(null); // el token de Turnstile es de un solo uso
      return;
    }

    // Con "Confirm email" activo, Supabase no devuelve un error cuando el
    // correo ya tiene cuenta (para no confirmarle a un atacante que ese
    // correo existe) — en vez de eso responde igual que un registro nuevo
    // pero con `identities: []`. Sin este chequeo, alguien que ya tiene
    // cuenta y se re-registra por error veía "revisa tu correo" como si se
    // hubiera creado algo, sin que llegara ningún email de verdad.
    if (data.user && data.user.identities && data.user.identities.length === 0) {
      setError(t.errores.correoYaRegistrado);
      setCaptchaToken(null);
      return;
    }

    setExito(true);
  }

  if (exito) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.auth.revisaTuCorreoTitulo}
        </h1>
        <p className="text-sm text-foreground-muted">
          {locale === "en" ? (
            <>
              We sent a confirmation link to <strong>{email}</strong>.{" "}
              {t.auth.revisaTuCorreoRegistro}
            </>
          ) : (
            <>
              Te enviamos un enlace de confirmación a <strong>{email}</strong>.{" "}
              {t.auth.revisaTuCorreoRegistro}
            </>
          )}
        </p>
      </div>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto"
    >
      <h1 className="font-display font-semibold text-lg mb-5">
        {t.auth.crearCuentaTitulo}
      </h1>

      <label htmlFor="registro-email" className="block text-[13px] font-medium mb-1.5">
        {t.auth.correo}
      </label>
      <input
        id="registro-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.correoPlaceholder}
      />

      <label htmlFor="registro-nombre" className="block text-[13px] font-medium mb-1.5">
        {t.auth.nombreLabel}
      </label>
      <input
        id="registro-nombre"
        required
        value={nombre}
        onChange={(e) => setNombre(e.target.value)}
        maxLength={100}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.nombrePlaceholder}
      />

      <label htmlFor="registro-telefono" className="block text-[13px] font-medium mb-1.5">
        {t.auth.telefonoLabel}
      </label>
      <input
        id="registro-telefono"
        type="tel"
        inputMode="tel"
        required
        value={telefono}
        onChange={(e) => setTelefono(e.target.value)}
        maxLength={30}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.telefonoPlaceholder}
      />

      <label htmlFor="registro-password" className="block text-[13px] font-medium mb-1.5">
        {t.auth.contrasena}
      </label>
      <input
        id="registro-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.contrasenaMinima}
      />

      <label htmlFor="registro-confirmar" className="block text-[13px] font-medium mb-1.5">
        {t.auth.confirmarContrasena}
      </label>
      <input
        id="registro-confirmar"
        type="password"
        required
        value={confirmar}
        onChange={(e) => setConfirmar(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="••••••••"
      />

      <label htmlFor="registro-codigo" className="block text-[13px] font-medium mb-1.5">
        {t.auth.codigoInvitacionLabel}
      </label>
      <input
        id="registro-codigo"
        value={codigoInvitacion}
        onChange={(e) => setCodigoInvitacion(e.target.value)}
        maxLength={20}
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.codigoInvitacionPlaceholder}
      />

      {error && (
        <p className="text-loss text-[13px] mb-3" role="alert">
          {error}
        </p>
      )}

      <div className="mb-4">
        <Turnstile onVerify={setCaptchaToken} onExpire={() => setCaptchaToken(null)} />
      </div>

      <button
        type="submit"
        disabled={cargando || (TURNSTILE_CONFIGURADO && !captchaToken)}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? t.auth.creandoCuenta : t.auth.crearCuenta}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        {t.auth.yaTienesCuenta}{" "}
        <Link href="/login" className="text-brand-primary font-semibold">
          {t.auth.iniciaSesion}
        </Link>
      </p>
    </form>
  );
}
