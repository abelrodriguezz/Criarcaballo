"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

const LIMITE_INACTIVIDAD_MS = 10 * 60 * 1000;
const CLAVE_ULTIMA_ACTIVIDAD = "trade4u-ultima-actividad";
const INTERVALO_CHEQUEO_MS = 15 * 1000;

const EVENTOS_ACTIVIDAD = [
  "mousedown",
  "mousemove",
  "keydown",
  "wheel",
  "touchstart",
  "scroll",
] as const;

/**
 * Cierra la sesión automáticamente tras 10 min sin interacción del usuario.
 * La marca de tiempo vive en localStorage (no en un estado de React) para
 * que la inactividad se mida entre TODAS las pestañas abiertas de la app:
 * si el usuario sigue activo en otra pestaña, esta no debe cerrar sesión.
 */
export function CierreInactividad() {
  const router = useRouter();
  const cerrandoRef = useRef(false);

  useEffect(() => {
    function marcarActividad() {
      try {
        localStorage.setItem(CLAVE_ULTIMA_ACTIVIDAD, String(Date.now()));
      } catch {
        // Storage no disponible (modo privado, etc.) — sin memoria entre
        // pestañas la sesión igual se cierra por el temporizador local.
      }
    }

    marcarActividad();
    EVENTOS_ACTIVIDAD.forEach((evento) =>
      window.addEventListener(evento, marcarActividad, { passive: true })
    );

    const intervalo = setInterval(async () => {
      if (cerrandoRef.current) return;

      let ultima = Date.now();
      try {
        ultima = Number(localStorage.getItem(CLAVE_ULTIMA_ACTIVIDAD)) || Date.now();
      } catch {
        // sin localStorage no hay forma de medir: no cerrar por las dudas.
        return;
      }

      if (Date.now() - ultima >= LIMITE_INACTIVIDAD_MS) {
        cerrandoRef.current = true;
        const supabase = crearClienteSupabase();
        await supabase.auth.signOut();
        router.push("/login?motivo=inactividad");
        router.refresh();
      }
    }, INTERVALO_CHEQUEO_MS);

    return () => {
      EVENTOS_ACTIVIDAD.forEach((evento) =>
        window.removeEventListener(evento, marcarActividad)
      );
      clearInterval(intervalo);
    };
  }, [router]);

  return null;
}
