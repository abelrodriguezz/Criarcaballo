"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { Usuario } from "@/lib/types";

export function FilaUsuarioAdmin({
  usuario,
  esUnoMismo,
}: {
  usuario: Usuario;
  esUnoMismo: boolean;
}) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function cambiarRol(nuevoRol: "user" | "admin") {
    if (esUnoMismo) return; // ver select deshabilitado — nunca debería llamarse

    setError(null);
    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("usuarios")
      .update({ role: nuevoRol })
      .eq("id", usuario.id);
    setGuardando(false);

    if (error) {
      setError("No se pudo actualizar el rol.");
      return;
    }
    router.refresh();
  }

  async function alternarActivo() {
    if (esUnoMismo) return; // ver botón deshabilitado abajo — nunca debería llamarse

    setError(null);
    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("usuarios")
      .update({ activo: !usuario.activo })
      .eq("id", usuario.id);
    setGuardando(false);

    if (error) {
      setError("No se pudo actualizar el estado.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3">
      <div className="min-w-0">
        {usuario.id_corto && (
          <div className="text-[11px] font-mono text-brand-primary font-semibold">
            ID: {usuario.id_corto}
          </div>
        )}
        <div className="text-sm font-medium break-all">
          {usuario.email}
          {esUnoMismo && (
            <span className="text-foreground-muted font-normal"> (tú)</span>
          )}
        </div>
        {usuario.wallet_usdt_erc20 && (
          <div className="text-[11px] text-foreground-muted font-mono truncate mt-0.5">
            {usuario.wallet_usdt_erc20}
          </div>
        )}
        {error && <p className="text-loss text-[12px] mt-0.5">{error}</p>}
      </div>

      <div className="flex items-center gap-2 shrink-0">
        <Link
          href={`/usuarios/${usuario.id}`}
          className="px-3 py-1.5 rounded-lg text-xs font-semibold text-brand-primary border border-[var(--border)] hover:bg-surface-hover transition-colors"
        >
          Ganancias
        </Link>

        <select
          aria-label="Rol"
          value={usuario.role}
          disabled={guardando || esUnoMismo}
          onChange={(e) => cambiarRol(e.target.value as "user" | "admin")}
          title={esUnoMismo ? "No puedes cambiar tu propio rol" : undefined}
          className="px-2.5 py-1.5 rounded-lg border border-[var(--border)] bg-background text-xs font-medium disabled:opacity-50"
        >
          <option value="user">Usuario</option>
          <option value="admin">Admin</option>
        </select>

        <button
          onClick={alternarActivo}
          disabled={guardando || esUnoMismo}
          title={esUnoMismo ? "No puedes desactivar tu propia cuenta" : undefined}
          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-colors disabled:opacity-50 ${
            usuario.activo
              ? "bg-gain/15 text-gain"
              : "bg-loss/15 text-loss"
          }`}
        >
          {usuario.activo ? "Activo" : "Desactivado"}
        </button>
      </div>
    </div>
  );
}
