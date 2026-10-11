"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

const LIMITE_INACTIVIDAD_MS = 10 * 60 * 1000;
const CLAVE_ULTIMA_ACTIVIDAD = "trade4u-ultima-actividad";
const INTERVALO_CHEQUEO_MS = 15 * 1000;

/**
 * Estampa "ahora" como última actividad. La llama TODA puerta de entrada que
 * deja al usuario con una sesión nueva (LoginForm al iniciar sesión,
 * RestablecerForm al guardar la contraseña nueva): como el montaje de
 * CierreInactividad ya no pisa un timestamp existente, sin esto una sesión
 * nueva heredaba el timestamp viejo de una sesión anterior en el mismo
 * navegador y se cerraba sola a los ~15 s de haber entrado.
 */
export function estamparActividadAhora() {
  try {
    localStorage.setItem(CLAVE_ULTIMA_ACTIVIDAD, String(Date.now()));
  } catch {
    // Storage no disponible — CierreInactividad ya maneja ese caso.
  }
}

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
    const marcarActividad = estamparActividadAhora;

    // NO se llama marcarActividad() aquí a secas: este efecto vuelve a
    // correr en cada montaje, incluida una recarga completa de la página
    // (ej. el celular suspendió la pestaña por estar en segundo plano un
    // rato largo y, al volver, el navegador la recarga de cero en vez de
    // reanudarla). Si se estampara "ahora" sin condición, esa recarga
    // borraba la única prueba de que el usuario de verdad estuvo inactivo
    // 10 minutos — el cierre por inactividad nunca llegaba a dispararse
    // ("a veces no funciona"). Solo se estampa si todavía no hay ningún
    // valor guardado (primera vez que se abre la app en este navegador);
    // un valor ya existente, por viejo que sea, se deja intacto para que
    // el chequeo de abajo lo pueda evaluar de verdad.
    try {
      if (!localStorage.getItem(CLAVE_ULTIMA_ACTIVIDAD)) {
        marcarActividad();
      }
    } catch {
      // Storage no disponible — no hay nada que inicializar.
    }
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
        try {
          const supabase = crearClienteSupabase();
          // scope "local": cierra SOLO la sesión de este navegador. El default
          // de supabase-js es "global" (revoca todas las sesiones de la
          // cuenta), y entonces una PC olvidada con la app abierta echaba al
          // usuario de su celular mientras lo estaba usando.
          await supabase.auth.signOut({ scope: "local" });
          router.push("/login?motivo=inactividad");
          router.refresh();
        } catch {
          // Si signOut falla (ej. sin red justo al despertar la laptop del
          // sueño, que es exactamente cuando este chequeo suele disparar
          // por primera vez), cerrandoRef se quedaba en true para siempre
          // y el cierre por inactividad dejaba de funcionar en esa pestaña
          // hasta recargar la página — "a veces no funciona". Se reintenta
          // en el próximo tick (ultima no se actualiza porque no hubo
          // actividad real, así que la condición sigue cumpliéndose).
          cerrandoRef.current = false;
        }
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
