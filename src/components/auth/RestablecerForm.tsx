"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import type { Diccionario, Locale } from "@/lib/i18n";

export function RestablecerForm({ t, locale }: { t: Diccionario; locale: Locale }) {
  const router = useRouter();
  const [listo, setListo] = useState(false);
  const [enlaceInvalido, setEnlaceInvalido] = useState(false);
  const [password, setPassword] = useState("");
  const [confirmar, setConfirmar] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [exito, setExito] = useState(false);
  const [cargando, setCargando] = useState(false);

  // El enlace del correo crea una sesión temporal de "recuperación" al
  // cargar la página. Esperamos a que el cliente termine de procesarla.
  useEffect(() => {
    const supabase = crearClienteSupabase();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((evento) => {
      if (evento === "PASSWORD_RECOVERY") {
        setListo(true);
      }
    });

    // Si la sesión de recuperación ya se procesó antes de que nos
    // suscribiéramos (carga rápida), la detectamos aquí también.
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) setListo(true);
    });

    return () => subscription.unsubscribe();
  }, []);

  // Si en unos segundos no se detectó una sesión de recuperación válida,
  // asumimos que el enlace venció o es inválido.
  useEffect(() => {
    const temporizador = setTimeout(() => {
      if (!listo) setEnlaceInvalido(true);
    }, 4000);
    return () => clearTimeout(temporizador);
  }, [listo]);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (password !== confirmar) {
      setError(t.auth.contrasenasNoCoinciden);
      return;
    }
    // 8 caracteres, igual que el registro. Estaba en 6 aquí: el usuario
    // podía poner una de 7, pasar esta validación y recibir el error
    // genérico de Supabase ("No se pudo actualizar la contraseña") sin
    // saber nunca cuál era el problema real.
    if (password.length < 8) {
      setError(t.auth.contrasenaCorta);
      return;
    }

    setCargando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.auth.updateUser({ password });
    setCargando(false);

    if (error) {
      setError(mensajeErrorAuth(error, t.auth.errorRestablecerGenerico, locale));
      return;
    }

    setExito(true);
    setTimeout(() => {
      router.push("/perfil");
      router.refresh();
    }, 1500);
  }

  if (exito) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.auth.contrasenaActualizadaTitulo}
        </h1>
        <p className="text-sm text-foreground-muted">{t.auth.redirigiendo}</p>
      </div>
    );
  }

  if (enlaceInvalido) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.auth.enlaceInvalidoTitulo}
        </h1>
        <p className="text-sm text-foreground-muted mb-4">
          {t.auth.enlaceInvalidoTexto}
        </p>
        <a
          href="/recuperar-contrasena"
          className="text-brand-primary font-semibold text-sm"
        >
          {t.auth.solicitarEnlaceNuevo}
        </a>
      </div>
    );
  }

  if (!listo) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <p className="text-sm text-foreground-muted">{t.auth.verificandoEnlace}</p>
      </div>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto"
    >
      <h1 className="font-display font-semibold text-lg mb-5">
        {t.auth.nuevaContrasenaTitulo}
      </h1>

      <label
        htmlFor="restablecer-password"
        className="block text-[13px] font-medium mb-1.5"
      >
        {t.auth.nuevaContrasenaTitulo}
      </label>
      <input
        id="restablecer-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.contrasenaMinima}
      />

      <label
        htmlFor="restablecer-confirmar"
        className="block text-[13px] font-medium mb-1.5"
      >
        {t.auth.confirmarContrasena}
      </label>
      <input
        id="restablecer-confirmar"
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

      <button
        type="submit"
        disabled={cargando}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? t.auth.guardando : t.auth.guardarNuevaContrasena}
      </button>
    </form>
  );
}
