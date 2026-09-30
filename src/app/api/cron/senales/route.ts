import { NextResponse } from "next/server";
import { revisarYCerrarSenalesActivas } from "@/lib/senales/verificarTpSl";

/**
 * Disparado por un cron real en Supabase (pg_cron + pg_net, ver migración
 * 080) cada cierto intervalo corto, para que el cierre automático de TP/SL
 * ya no dependa de que alguien visite /senales — antes, si nadie entraba a
 * la página, una señal que tocó su nivel se quedaba "activa" en la UI
 * indefinidamente (el resultado seguía siendo correcto en la próxima
 * visita, porque se revisan las velas históricas, no el precio del
 * momento, pero podía tardar horas o días en reflejarse).
 *
 * Reutiliza la MISMA función que usa /senales — nada de lógica nueva de
 * TP/SL aquí, solo el disparador.
 *
 * Protegido con el mismo TRADING_SERVER_SECRET que ya usan abrir_operacion
 * y cerrar_senal_automatica (en vez de una variable nueva): el valor
 * también vive espejado en config_servidor (migración 019), así que el
 * cron de Supabase lo puede leer de ahí sin que haga falta configurar
 * nada adicional en Railway.
 */
export async function POST(request: Request) {
  const secretoEsperado = process.env.TRADING_SERVER_SECRET;
  if (!secretoEsperado) {
    return NextResponse.json(
      { ok: false, error: "TRADING_SERVER_SECRET no configurado en el servidor." },
      { status: 500 }
    );
  }

  const auth = request.headers.get("authorization") ?? "";
  const recibido = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  if (recibido !== secretoEsperado) {
    return NextResponse.json({ ok: false, error: "No autorizado." }, { status: 401 });
  }

  try {
    await revisarYCerrarSenalesActivas();
    return NextResponse.json({ ok: true });
  } catch (e) {
    console.error("[cron/senales] falló la revisión automática:", e);
    return NextResponse.json({ ok: false, error: "Error interno." }, { status: 500 });
  }
}
