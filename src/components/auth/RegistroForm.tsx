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

export function RegistroForm({ t, locale }: { t: Diccionario; locale: Locale }) {
  const searchParams = useSearchParams();
  const codigoRef = searchParams.get("ref");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmar, setConfirmar] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exito, setExito] = useState(false);
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

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

    setCargando(true);
    const supabase = crearClienteSupabase();
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        ...(captchaToken ? { captchaToken } : {}),
        ...(codigoRef ? { data: { ref: codigoRef } } : {}),
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
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="••••••••"
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
