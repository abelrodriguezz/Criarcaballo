import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

const CLAVE = "premio_referido";

export const PORCENTAJE_REFERIDO_POR_DEFECTO = 10;
export const BONO_CADA_POR_DEFECTO = 10;
export const BONO_MONTO_POR_DEFECTO = 1000;

export interface ConfigPremioReferido {
  porcentaje: number;
  bonoCada: number;
  bonoMonto: number;
}

/**
 * Cómo se paga hoy un referido:
 * - Comisión: `porcentaje`% del monto que el invitado carga en SU
 *   depósito simulado (una vez por usuario, ver migración 026). Si nunca
 *   deposita, no genera comisión — la migración 034 lo calcula solo, con
 *   un trigger sobre `depositos_simulados`, no desde aquí.
 * - Bono: cada `bonoCada` referidos "calificados" (que ya depositaron) se
 *   suma un bono fijo de `bonoMonto`, repetible (10, 20, 30...).
 */
export async function obtenerConfigPremioReferido(): Promise<ConfigPremioReferido> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("valor")
    .eq("clave", CLAVE)
    .maybeSingle();

  const valor = data?.valor as Partial<{
    porcentaje: number;
    bono_cada: number;
    bono_monto: number;
  }> | null;

  return {
    porcentaje:
      typeof valor?.porcentaje === "number" && valor.porcentaje >= 0
        ? valor.porcentaje
        : PORCENTAJE_REFERIDO_POR_DEFECTO,
    bonoCada:
      typeof valor?.bono_cada === "number" && valor.bono_cada > 0
        ? valor.bono_cada
        : BONO_CADA_POR_DEFECTO,
    bonoMonto:
      typeof valor?.bono_monto === "number" && valor.bono_monto >= 0
        ? valor.bono_monto
        : BONO_MONTO_POR_DEFECTO,
  };
}
