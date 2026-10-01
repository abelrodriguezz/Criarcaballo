"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerUsuarioActual, esAdmin } from "@/lib/auth/sesion";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";

/**
 * Elimina el pick del día indicado (solo admin). No hay "editar": para
 * cambiarlo, se borra el actual y se define uno nuevo — así queda un solo
 * pick vigente a la vez en vez de acumular filas sin fin en la tabla.
 */
export async function eliminarPickDelDia(pickId: string): Promise<Resultado<null>> {
  const usuario = await obtenerUsuarioActual();
  if (!usuario || !esAdmin(usuario)) {
    return fallo("Solo un admin puede hacer esto.");
  }

  const supabase = await crearClienteSupabaseServidor();
  const { error } = await supabase.from("pick_del_dia").delete().eq("id", pickId);

  if (error) {
    // P0001 = RAISE EXCEPTION de un trigger nuestro: el de la migración 083
    // (proteger_borrado_pick_del_dia) bloquea borrar un pick que todavía
    // tiene operaciones abiertas. Su mensaje ya está redactado para el
    // admin ("Ciérralas primero desde..."); con el genérico de antes el
    // admin no tenía forma de saber por qué no se borraba.
    return fallo(
      error.code === "P0001" && error.message
        ? error.message
        : "No se pudo eliminar el pick."
    );
  }

  revalidatePath("/trade-del-dia");
  return exito(null);
}

/** Lo que el admin escribe una vez por símbolo para cerrar en bloque. */
export interface DatosCierreSimbolo {
  precioEntrada: number;
  precioSalida: number;
  /** ISO 8601. Si no se manda, la operación conserva su hora de apertura real. */
  horaEntrada?: string;
  /** ISO 8601. Si no se manda, se usa el momento en que se ejecuta el cierre. */
  horaCierre?: string;
}

/**
 * Cierra TODAS las operaciones abiertas de TODOS los usuarios, usando un
 * precio de ENTRADA y uno de SALIDA que el propio admin escribe por cada
 * símbolo (no se consulta Binance para ninguno de los dos) — así el admin
 * controla exactamente a qué precios se liquida la sesión, sin depender de
 * que el precio capturado en vivo al abrir haya sido correcto (símbolo mal
 * escrito, par no disponible, bloqueo geográfico, etc. — migración 056).
 * Cada operación conserva su propio monto_usado (lo que ESE usuario
 * invirtió), así que el mismo precio en bloque produce una ganancia/pérdida
 * distinta en dólares por usuario.
 */
export interface ResultadoCierreMasivo {
  cerradas: number;
  /**
   * Símbolos que tenían operaciones abiertas pero para los que no se
   * recibió precio de salida — normalmente porque alguien abrió una
   * operación después de que el admin cargó la pantalla, así que ese
   * símbolo no estaba en el formulario. Esas operaciones siguen abiertas.
   */
  sinPrecio: string[];
}

export async function adminCerrarTodasLasOperaciones(
  datosPorSimbolo: Record<string, DatosCierreSimbolo>
): Promise<Resultado<ResultadoCierreMasivo>> {
  const usuario = await obtenerUsuarioActual();
  if (!usuario || !esAdmin(usuario)) {
    return fallo("Solo un admin puede hacer esto.");
  }

  const supabase = await crearClienteSupabaseServidor();
  // Desde la migración 019 el admin sí ve las operaciones de todos los
  // usuarios (antes RLS le devolvía solo las suyas y este cierre masivo
  // no cerraba nada de nadie más).
  const { data: abiertas, error: errorLectura } = await supabase
    .from("operaciones_simuladas")
    .select("id, activo, created_at")
    .eq("estado", "abierta");

  if (errorLectura) {
    return fallo(
      "No se pudo leer la lista de operaciones abiertas: " + errorLectura.message
    );
  }

  if (!abiertas || abiertas.length === 0) {
    return exito({ cerradas: 0, sinPrecio: [] });
  }

  // Validación de horas ANTES de cerrar nada: la base (migración 069)
  // rechaza igual cada operación con hora de entrada >= hora de cierre,
  // pero como se cierra una por una, un símbolo con horas válidas quedaba
  // liquidado y otro con horas inválidas no — cierre a medias. Se compara
  // con los valores efectivos: sin hora de entrada cuenta la apertura real
  // de la operación; sin hora de cierre, el momento actual.
  const ahora = Date.now();
  for (const [simbolo, datos] of Object.entries(datosPorSimbolo)) {
    const entrada = datos.horaEntrada ? Date.parse(datos.horaEntrada) : null;
    const cierre = datos.horaCierre ? Date.parse(datos.horaCierre) : ahora;
    if ((entrada !== null && Number.isNaN(entrada)) || Number.isNaN(cierre)) {
      return fallo(`Hora inválida para ${simbolo}. No se cerró ninguna operación.`);
    }
    const aperturas = abiertas.filter((op) => op.activo === simbolo);
    const conflicto = aperturas.some(
      (op) => (entrada ?? Date.parse(op.created_at)) >= cierre
    );
    if (conflicto) {
      return fallo(
        `${simbolo}: la hora de entrada debe ser anterior a la hora de cierre` +
          (entrada === null
            ? " (sin hora de entrada se usa la hora real en que se abrió cada operación)."
            : ".") +
          " No se cerró ninguna operación."
      );
    }
  }

  const sinPrecio = new Set<string>();
  const cierres: {
    operacion_id: string;
    precio_entrada: number;
    precio_salida: number;
    hora_entrada: string | null;
    hora_cierre: string | null;
  }[] = [];

  for (const op of abiertas) {
    const datos = datosPorSimbolo[op.activo];
    const entradaValida =
      datos && Number.isFinite(datos.precioEntrada) && datos.precioEntrada > 0;
    const salidaValida =
      datos && Number.isFinite(datos.precioSalida) && datos.precioSalida > 0;
    if (!entradaValida || !salidaValida) {
      sinPrecio.add(op.activo);
      continue;
    }

    cierres.push({
      operacion_id: op.id,
      precio_entrada: datos.precioEntrada,
      precio_salida: datos.precioSalida,
      hora_entrada: datos.horaEntrada ?? null,
      hora_cierre: datos.horaCierre ?? null,
    });
  }

  if (cierres.length === 0) {
    return exito({ cerradas: 0, sinPrecio: [...sinPrecio] });
  }

  // Una sola llamada RPC: adentro de admin_cerrar_operaciones_bloque (migración
  // 071) todo el bucle corre como una única transacción de Postgres. Si UNA
  // sola operación falla (precio inválido, horas invertidas, ya estaba
  // cerrada), la función entera revierte — no queda un cierre a medias.
  const { data: cerradas, error } = await supabase.rpc(
    "admin_cerrar_operaciones_bloque",
    { p_cierres: cierres }
  );

  if (error) {
    // "⚠️" a propósito: sin nada que lo distinga, un admin apurado puede
    // confundir este aviso con el "cerradas" de un cierre exitoso y no
    // notar que, en realidad, NO se cerró nada (queda todo como estaba).
    return fallo(
      `⚠️ No se cerró ninguna operación: ${error.message || "error desconocido"}.`
    );
  }

  revalidatePath("/trade-del-dia");
  revalidatePath("/usuarios");

  return exito({ cerradas: cerradas?.length ?? 0, sinPrecio: [...sinPrecio] });
}
