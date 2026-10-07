"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { Turnstile } from "@/components/auth/Turnstile";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import type { Diccionario, Locale } from "@/lib/i18n";

// Sin site key configurada, Turnstile no puede renderizar un widget real y
// nunca llegaría un captchaToken — en ese caso el captcha se omite en vez
// de dejar el formulario deshabilitado para siempre. Supabase igual solo
// exige el token cuando tú actives "Attack Protection" con la secret key.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

export function LoginForm({
  t,
  locale,
  cerradaPorInactividad,
}: {
  t: Diccionario;
  locale: Locale;
  cerradaPorInactividad?: boolean;
}) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [aceptaTerminos, setAceptaTerminos] = useState(false);
  const [error, setError] = useState<string | null>(
    cerradaPorInactividad ? t.auth.sesionCerradaPorInactividad : null
  );
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!aceptaTerminos) {
      setError(t.auth.debesAceptarTerminos);
      return;
    }

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
      // Antes TODO error se mostraba como "Correo o contraseña incorrectos",
      // incluido `email_not_confirmed`: quien se registró y aún no confirmó
      // el correo (o nunca le llegó, sin SMTP propio) creía que había escrito
      // mal la contraseña y reintentaba en bucle. Credenciales inválidas
      // siguen cayendo en el mensaje de respaldo.
      setError(mensajeErrorAuth(error, t.auth.correoIncorrecto, locale));
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
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.correoPlaceholder}
      />

      <div className="flex justify-between items-baseline gap-2 mb-1.5">
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

      <label className="flex items-start gap-2 mb-4 text-[13px] text-foreground-muted cursor-pointer">
        <input
          type="checkbox"
          checked={aceptaTerminos}
          onChange={(e) => setAceptaTerminos(e.target.checked)}
          className="mt-0.5 shrink-0"
        />
        <span>
          {t.auth.aceptoLosPrefijo}
          <Link
            href="/terminos"
            target="_blank"
            className="text-brand-primary font-semibold underline"
          >
            {t.auth.terminosYCondiciones}
          </Link>
        </span>
      </label>

      <button
        type="submit"
        disabled={cargando || !aceptaTerminos || (TURNSTILE_CONFIGURADO && !captchaToken)}
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
