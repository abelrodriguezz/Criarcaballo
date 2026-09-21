"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { Turnstile } from "@/components/auth/Turnstile";
import type { Diccionario, Locale } from "@/lib/i18n";

// Sin site key configurada, Turnstile no puede renderizar un widget real y
// nunca llegaría un captchaToken — en ese caso el captcha se omite en vez
// de dejar el formulario deshabilitado para siempre. Supabase igual solo
// exige el token cuando tú actives "Attack Protection" con la secret key.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

// `locale` no se usa en este formulario en particular (no pasa por
// mensajeErrorAuth), pero se recibe para que las 4 páginas de auth tengan
// la misma firma y no haya que recordar cuál sí la necesita.
export function LoginForm({ t }: { t: Diccionario; locale: Locale }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
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
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
      options: captchaToken ? { captchaToken } : undefined,
    });

    setCargando(false);

    if (error || !data.user) {
      setError(t.auth.correoIncorrecto);
      setCaptchaToken(null); // el token de Turnstile es de un solo uso
      return;
    }

    const { data: perfil } = await supabase
      .from("usuarios")
      .select("activo")
      .eq("id", data.user.id)
      .single();

    if (perfil && perfil.activo === false) {
      await supabase.auth.signOut();
      setError(t.auth.cuentaDesactivadaLogin);
      setCaptchaToken(null);
      return;
    }

    router.push("/perfil");
    router.refresh();
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto"
    >
      <h1 className="font-display font-semibold text-lg mb-5">
        {t.auth.iniciarSesionTitulo}
      </h1>

      <label htmlFor="login-email" className="block text-[13px] font-medium mb-1.5">
        {t.auth.correo}
      </label>
      <input
        id="login-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.correoPlaceholder}
      />

      <div className="flex justify-between items-baseline mb-1.5">
        <label htmlFor="login-password" className="block text-[13px] font-medium">
          {t.auth.contrasena}
        </label>
        <Link
          href="/recuperar-contrasena"
          className="text-[12px] text-brand-primary font-semibold"
        >
          {t.auth.olvidasteContrasena}
        </Link>
      </div>
      <input
        id="login-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
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
        {cargando ? t.auth.ingresando : t.auth.iniciarSesionTitulo}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        {t.auth.noTienesCuenta}{" "}
        <Link href="/registro" className="text-brand-primary font-semibold">
          {t.auth.registrate}
        </Link>
      </p>
    </form>
  );
}
