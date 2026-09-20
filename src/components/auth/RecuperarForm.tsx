"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import { Turnstile } from "@/components/auth/Turnstile";

// Ver nota en LoginForm.tsx: sin site key configurada, el captcha se omite
// en vez de dejar el formulario deshabilitado para siempre.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

export function RecuperarForm() {
  const [email, setEmail] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (TURNSTILE_CONFIGURADO && !captchaToken) {
      setError("Completa la verificación antes de continuar.");
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
      setError(
        mensajeErrorAuth(
          error,
          "No se pudo procesar la solicitud. Intenta de nuevo."
        )
      );
      setCaptchaToken(null);
    }
  }

  if (enviado) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          Revisa tu correo
        </h1>
        <p className="text-sm text-foreground-muted">
          Si <strong>{email}</strong> tiene una cuenta, te enviamos un enlace
          para restablecer tu contraseña.
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
        Recuperar contraseña
      </h1>
      <p className="text-[13px] text-foreground-muted mb-5">
        Te enviaremos un enlace a tu correo para crear una nueva contraseña.
      </p>

      <label className="block text-[13px] font-medium mb-1.5">
        Correo electrónico
      </label>
      <input
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="tucorreo@ejemplo.com"
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
        {cargando ? "Enviando..." : "Enviar enlace"}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        <Link href="/login" className="text-brand-primary font-semibold">
          ← Volver a iniciar sesión
        </Link>
      </p>
    </form>
  );
}
