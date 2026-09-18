"use client";

import { useMemo, useState } from "react";
import { FilaUsuarioAdmin } from "@/components/admin/FilaUsuarioAdmin";
import type { Usuario } from "@/lib/types";

export function ListaUsuariosAdmin({
  usuarios,
  miId,
}: {
  usuarios: Usuario[];
  miId: string;
}) {
  const [busqueda, setBusqueda] = useState("");

  const filtrados = useMemo(() => {
    const termino = busqueda.trim().toLowerCase();
    if (!termino) return usuarios;

    return usuarios.filter((u) => {
      const coincideId = u.id_corto != null && String(u.id_corto).includes(termino);
      const coincideEmail = u.email.toLowerCase().includes(termino);
      return coincideId || coincideEmail;
    });
  }, [usuarios, busqueda]);

  return (
    <div>
      <input
        value={busqueda}
        onChange={(e) => setBusqueda(e.target.value)}
        placeholder="Buscar por ID o correo..."
        aria-label="Buscar usuario"
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      {filtrados.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Ningún usuario coincide con &quot;{busqueda}&quot;.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {filtrados.map((u) => (
            <FilaUsuarioAdmin key={u.id} usuario={u} esUnoMismo={u.id === miId} />
          ))}
        </div>
      )}
    </div>
  );
}
