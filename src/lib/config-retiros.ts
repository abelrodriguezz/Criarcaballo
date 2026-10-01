import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

const CLAVE = "fee_retiro";

/** Sin fee hasta que el admin configure uno explícitamente. */
export const FEE_RETIRO_POR_DEFECTO = 0;

/**
 * % que se le resta al usuario del monto que PIDE retirar (pide $50 con
 * 10% de fee, se le transfieren $45). No afecta cuánto consume del fondo
 * de ganancias pendientes -- eso sigue siendo el monto bruto pedido; el
 * fee es la diferencia entre lo que se descontó de su fondo y lo que de
 * verdad se le transfiere por wallet.
 */
export async function obtenerFeeRetiro(): Promise<number> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("valor")
    .eq("clave", CLAVE)
    .maybeSingle();

  const valor = data?.valor as Partial<{ porcentaje: number }> | null;

  return typeof valor?.porcentaje === "number" &&
    valor.porcentaje >= 0 &&
    valor.porcentaje <= 100
    ? valor.porcentaje
    : FEE_RETIRO_POR_DEFECTO;
}
