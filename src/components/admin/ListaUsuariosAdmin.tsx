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

  // Se calcula una sola vez a partir de la lista completa — cada usuario
  // ya trae su propio invitado_por, así que contar cuántos apuntan a cada
  // id no necesita ninguna consulta extra a la base de datos.
  const conteoInvitados = useMemo(() => {
    const mapa = new Map<string, number>();
    for (const u of usuarios) {
      if (!u.invitado_por) continue;
      mapa.set(u.invitado_por, (mapa.get(u.invitado_por) ?? 0) + 1);
    }
    return mapa;
  }, [usuarios]);

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
            <FilaUsuarioAdmin
              key={u.id}
              usuario={u}
              esUnoMismo={u.id === miId}
              cantidadInvitados={conteoInvitados.get(u.id) ?? 0}
            />
          ))}
        </div>
      )}
    </div>
  );
}
