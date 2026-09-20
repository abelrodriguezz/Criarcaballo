"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerUsuarioActual, esAdmin } from "@/lib/auth/sesion";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";

/**
 * Cierra TODAS las operaciones abiertas de TODOS los usuarios, usando un
 * precio de salida que el propio admin escribe por cada símbolo (no se
 * consulta Binance) — así el admin controla exactamente a qué precio se
 * liquida la sesión. Cada operación usa su propio precio de entrada
 * (guardado desde que se abrió) contra este precio de salida para
 * calcular la ganancia/pérdida de cada usuario.
 */
export interface ResultadoCierreMasivo {
  cerradas: number;
  fallidas: number;
  /**
   * Símbolos que tenían operaciones abiertas pero para los que no se
   * recibió precio de salida — normalmente porque alguien abrió una
   * operación después de que el admin cargó la pantalla, así que ese
   * símbolo no estaba en el formulario. Esas operaciones siguen abiertas.
   */
  sinPrecio: string[];
  /**
   * Motivo del primer cierre que falló, para poder mostrarlo. Sin esto el
   * admin solo veía "N fallaron" y no tenía forma de saber por qué.
   */
  motivoFallo: string | null;
}

export async function adminCerrarTodasLasOperaciones(
  preciosPorSimbolo: Record<string, number>
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
    .select("id, activo")
    .eq("estado", "abierta");

  if (errorLectura) {
    return fallo(
      "No se pudo leer la lista de operaciones abiertas: " + errorLectura.message
    );
  }

  if (!abiertas || abiertas.length === 0) {
    return exito({ cerradas: 0, fallidas: 0, sinPrecio: [], motivoFallo: null });
  }

  let cerradas = 0;
  let fallidas = 0;
  let motivoFallo: string | null = null;
  const sinPrecio = new Set<string>();

  for (const op of abiertas) {
    const precio = preciosPorSimbolo[op.activo];
    if (typeof precio !== "number" || !Number.isFinite(precio) || precio <= 0) {
      sinPrecio.add(op.activo);
      continue;
    }

    const { error } = await supabase.rpc("admin_cerrar_operacion", {
      p_operacion_id: op.id,
      p_precio_salida: precio,
    });

    if (error) {
      fallidas++;
      motivoFallo ??= error.message || null;
    } else {
      cerradas++;
    }
  }

  revalidatePath("/trade-del-dia");
  revalidatePath("/usuarios");

  return exito({ cerradas, fallidas, sinPrecio: [...sinPrecio], motivoFallo });
}
