"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";

export function RestablecerForm() {
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
    const t = setTimeout(() => {
      if (!listo) setEnlaceInvalido(true);
    }, 4000);
    return () => clearTimeout(t);
  }, [listo]);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (password !== confirmar) {
      setError("Las contraseñas no coinciden.");
      return;
    }
    // 8 caracteres, igual que el registro. Estaba en 6 aquí: el usuario
    // podía poner una de 7, pasar esta validación y recibir el error
    // genérico de Supabase ("No se pudo actualizar la contraseña") sin
    // saber nunca cuál era el problema real.
    if (password.length < 8) {
      setError("La contraseña debe tener al menos 8 caracteres.");
      return;
    }

    setCargando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.auth.updateUser({ password });
    setCargando(false);

    if (error) {
      setError(
        mensajeErrorAuth(
          error,
          "No se pudo actualizar la contraseña. Intenta de nuevo."
        )
      );
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
          Contraseña actualizada
        </h1>
        <p className="text-sm text-foreground-muted">Redirigiendo...</p>
      </div>
    );
  }

  if (enlaceInvalido) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          Enlace inválido o vencido
        </h1>
        <p className="text-sm text-foreground-muted mb-4">
          Los enlaces de recuperación expiran después de un tiempo. Solicita
          uno nuevo.
        </p>
        <a
          href="/recuperar-contrasena"
          className="text-brand-primary font-semibold text-sm"
        >
          Solicitar enlace nuevo
        </a>
      </div>
    );
  }

  if (!listo) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <p className="text-sm text-foreground-muted">Verificando enlace...</p>
      </div>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto"
    >
      <h1 className="font-display font-semibold text-lg mb-5">
        Nueva contraseña
      </h1>

      <label
        htmlFor="restablecer-password"
        className="block text-[13px] font-medium mb-1.5"
      >
        Nueva contraseña
      </label>
      <input
        id="restablecer-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="Mínimo 8 caracteres"
      />

      <label
        htmlFor="restablecer-confirmar"
        className="block text-[13px] font-medium mb-1.5"
      >
        Confirmar contraseña
      </label>
      <input
        id="restablecer-confirmar"
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

      <button
        type="submit"
        disabled={cargando}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? "Guardando..." : "Guardar nueva contraseña"}
      </button>
    </form>
  );
}
