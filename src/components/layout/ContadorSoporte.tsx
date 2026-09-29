"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

const ContextoContador = createContext(0);

/**
 * Contador de mensajes de soporte sin leer para la campanita del NavBar y
 * el puntito de "Perfil" en la barra mobile.
 *
 * Antes el número se calculaba SOLO en el layout raíz (Server Component),
 * y en el App Router el layout raíz no se vuelve a renderizar en una
 * navegación suave (clic en un <Link>): la campanita quedaba congelada con
 * el valor de la última carga completa. Reproducido contra `next build &&
 * next start`: el admin abría la conversación y la campana seguía en el
 * número viejo; un mensaje nuevo no aparecía hasta recargar; y hasta en
 * una carga directa de /soporte el contador salía viejo, porque el layout
 * cuenta en paralelo a la página que marca los mensajes como leídos.
 *
 * El valor del servidor se usa como punto de partida (sin parpadeo en la
 * primera pintada) y se vuelve a consultar en cada cambio de ruta — cuando
 * cambia el pathname la página nueva ya terminó de renderizar en el
 * servidor, así que su marcarLeidoPor* ya corrió — y al volver a la
 * pestaña. Misma consulta que el layout, con la sesión del propio usuario
 * (RLS decide qué filas cuenta).
 */
export function ContadorSoporteProvider({
  inicial,
  usuarioId,
  esAdmin,
  children,
}: {
  inicial: number;
  usuarioId: string | null;
  esAdmin: boolean;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const [contador, setContador] = useState(inicial);

  useEffect(() => {
    if (!usuarioId) return;
    let cancelado = false;
    const supabase = crearClienteSupabase();

    async function actualizar() {
      const consulta = supabase
        .from("mensajes_soporte")
        .select("id", { count: "exact", head: true });
      const { count, error } = esAdmin
        ? await consulta.eq("leido_admin", false)
        : await consulta.eq("usuario_id", usuarioId!).eq("leido_usuario", false);
      // Si la consulta falla (red caída) se deja el último valor conocido
      // en vez de apagar la campanita en falso.
      if (!cancelado && !error) setContador(count ?? 0);
    }

    function alVolverALaPestana() {
      if (document.visibilityState === "visible") actualizar();
    }

    actualizar();
    document.addEventListener("visibilitychange", alVolverALaPestana);
    return () => {
      cancelado = true;
      document.removeEventListener("visibilitychange", alVolverALaPestana);
    };
  }, [pathname, usuarioId, esAdmin]);

  // Sin sesión no hay campanita que mostrar (y un valor viejo de una
  // sesión anterior no debe filtrarse).
  return <ContextoContador.Provider value={usuarioId ? contador : 0}>{children}</ContextoContador.Provider>;
}

export function useMensajesSinLeer(): number {
  return useContext(ContextoContador);
}
