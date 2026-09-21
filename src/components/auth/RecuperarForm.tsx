"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import { Turnstile } from "@/components/auth/Turnstile";
import type { Diccionario, Locale } from "@/lib/i18n";

// Ver nota en LoginForm.tsx: sin site key configurada, el captcha se omite
// en vez de dejar el formulario deshabilitado para siempre.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

export function RecuperarForm({ t, locale }: { t: Diccionario; locale: Locale }) {
  const [email, setEmail] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (TURNSTILE_CONFIGURADO && !captchaToken) {
      setError(t.auth.completaVerificacion);
      return;
    }

    setCargando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/restablecer-contrasena`,
      ...(captchaToken ? { captchaToken } : {}),
    });
    setCargando(false);

    // Se muestra el mismo mensaje exista o no la cuenta — así no se revela
    // desde afuera qué correos están registrados en la plataforma.
    if (!error) {
      setEnviado(true);
    } else {
      setError(mensajeErrorAuth(error, t.auth.errorRecuperarGenerico, locale));
      setCaptchaToken(null);
    }
  }

  if (enviado) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.auth.revisaTuCorreoTitulo}
        </h1>
        <p className="text-sm text-foreground-muted">
          {locale === "en" ? (
            <>
              If <strong>{email}</strong> {t.auth.revisaTuCorreoRecuperar}
            </>
          ) : (
            <>
              Si <strong>{email}</strong> {t.auth.revisaTuCorreoRecuperar}
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
      <h1 className="font-display font-semibold text-lg mb-2">
        {t.auth.recuperarTitulo}
      </h1>
      <p className="text-[13px] text-foreground-muted mb-5">
        {t.auth.recuperarSubtitulo}
      </p>

      <label className="block text-[13px] font-medium mb-1.5">
        {t.auth.correo}
      </label>
      <input
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.correoPlaceholder}
      />

      {error && (
        <p className="text-loss text-[13px] mb-3" role="alert">
          {error}
        </p>
      )}

      <div className="mb-4">
        <Turnstile
          onVerify={setCaptchaToken}
          onExpire={() => setCaptchaToken(null)}
        />
      </div>

      <button
        type="submit"
        disabled={cargando || (TURNSTILE_CONFIGURADO && !captchaToken)}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? t.auth.enviando : t.auth.enviarEnlace}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        <Link href="/login" className="text-brand-primary font-semibold">
          {t.auth.volverAIniciarSesion}
        </Link>
      </p>
    </form>
  );
}
