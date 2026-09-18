"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { Turnstile } from "@/components/auth/Turnstile";

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!captchaToken) {
      setError("Completa la verificación antes de continuar.");
      return;
    }

    setCargando(true);

    const supabase = crearClienteSupabase();
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
      options: { captchaToken },
    });

    setCargando(false);

    if (error || !data.user) {
      setError("Correo o contraseña incorrectos.");
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
      setError("Esta cuenta fue desactivada. Contacta al equipo de soporte.");
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
        Iniciar sesión
      </h1>

      <label htmlFor="login-email" className="block text-[13px] font-medium mb-1.5">
        Correo electrónico
      </label>
      <input
        id="login-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="tucorreo@ejemplo.com"
      />

      <div className="flex justify-between items-baseline mb-1.5">
        <label htmlFor="login-password" className="block text-[13px] font-medium">
          Contraseña
        </label>
        <Link
          href="/recuperar-contrasena"
          className="text-[12px] text-brand-primary font-semibold"
        >
          ¿Olvidaste tu contraseña?
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
        disabled={cargando || !captchaToken}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? "Ingresando..." : "Iniciar sesión"}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        ¿No tienes cuenta?{" "}
        <Link href="/registro" className="text-brand-primary font-semibold">
          Regístrate
        </Link>
      </p>
    </form>
  );
}
