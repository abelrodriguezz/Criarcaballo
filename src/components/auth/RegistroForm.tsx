"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import { Turnstile } from "@/components/auth/Turnstile";

// Ver nota en LoginForm.tsx: sin site key configurada, el captcha se omite
// en vez de dejar el formulario deshabilitado para siempre.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

export function RegistroForm() {
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
      setError("Las contraseñas no coinciden.");
      return;
    }
    if (password.length < 8) {
      setError("La contraseña debe tener al menos 8 caracteres.");
      return;
    }
    if (TURNSTILE_CONFIGURADO && !captchaToken) {
      setError("Completa la verificación antes de continuar.");
      return;
    }

    setCargando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        ...(captchaToken ? { captchaToken } : {}),
        ...(codigoRef ? { data: { ref: codigoRef } } : {}),
      },
    });
    setCargando(false);

    if (error) {
      setError(
        mensajeErrorAuth(error, "No se pudo crear la cuenta. Intenta de nuevo.")
      );
      setCaptchaToken(null); // el token de Turnstile es de un solo uso
      return;
    }

    setExito(true);
  }

  if (exito) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          Revisa tu correo
        </h1>
        <p className="text-sm text-foreground-muted">
          Te enviamos un enlace de confirmación a <strong>{email}</strong>.
          Confírmalo para poder iniciar sesión.
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
        Crear cuenta
      </h1>

      <label htmlFor="registro-email" className="block text-[13px] font-medium mb-1.5">
        Correo electrónico
      </label>
      <input
        id="registro-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="tucorreo@ejemplo.com"
      />

      <label htmlFor="registro-password" className="block text-[13px] font-medium mb-1.5">
        Contraseña
      </label>
      <input
        id="registro-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="Mínimo 8 caracteres"
      />

      <label htmlFor="registro-confirmar" className="block text-[13px] font-medium mb-1.5">
        Confirmar contraseña
      </label>
      <input
        id="registro-confirmar"
        type="password"
        required
        value={confirmar}
        onChange={(e) => setConfirmar(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
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
        {cargando ? "Creando cuenta..." : "Crear cuenta"}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        ¿Ya tienes cuenta?{" "}
        <Link href="/login" className="text-brand-primary font-semibold">
          Inicia sesión
        </Link>
      </p>
    </form>
  );
}
