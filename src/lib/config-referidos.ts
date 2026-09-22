import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

const CLAVE = "premio_referido";

export const PREMIO_REFERIDO_POR_DEFECTO = 5;

interface ConfigPremioReferido {
  monto: number;
}

/** Monto en USDT que se le otorga a quien invita, por cada persona que se registra con su código. */
export async function obtenerPremioReferido(): Promise<number> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("valor")
    .eq("clave", CLAVE)
    .maybeSingle();

  const monto = (data?.valor as ConfigPremioReferido | null)?.monto;
  return typeof monto === "number" && monto > 0 ? monto : PREMIO_REFERIDO_POR_DEFECTO;
}

export { CLAVE as CLAVE_PREMIO_REFERIDO };
