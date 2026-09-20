import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerSecretoServidor } from "@/lib/supabase/secretoServidor";
import type { Senal } from "@/lib/types";

/** Solo un par de Binance con este formato se puede consultar en su API. */
const FORMATO_PAR_BINANCE = /^[A-Z0-9]{5,20}$/;

/** Máximo de velas que Binance devuelve en una sola request. */
const MAX_VELAS = 1000;

/**
 * Intervalos de vela de Binance, de más fino a más grueso, con cuántos
 * minutos cubre cada uno en una sola request de MAX_VELAS velas.
 * Se elige el más fino que alcance a cubrir todo el tiempo que la señal
 * lleva activa — si se eligiera uno demasiado fino, las 1000 velas se
 * acabarían antes de llegar a "ahora" y un toque de TP/SL reciente
 * pasaría desapercibido para siempre.
 *
 * La versión anterior se detenía en "4h" (≈166 días), así que una señal
 * más vieja que eso dejaba de revisarse correctamente sin ningún aviso.
 */
const INTERVALOS: ReadonlyArray<{ nombre: string; minutosPorVela: number }> = [
  { nombre: "1m", minutosPorVela: 1 },
  { nombre: "5m", minutosPorVela: 5 },
  { nombre: "15m", minutosPorVela: 15 },
  { nombre: "1h", minutosPorVela: 60 },
  { nombre: "4h", minutosPorVela: 240 },
  { nombre: "1d", minutosPorVela: 1440 },
  { nombre: "1w", minutosPorVela: 10080 },
];

function elegirIntervalo(msTranscurridos: number): string {
  const minutos = msTranscurridos / 60000;
  for (const intervalo of INTERVALOS) {
    if (minutos <= intervalo.minutosPorVela * MAX_VELAS) return intervalo.nombre;
  }
  // Una señal de más de ~19 años: no hay intervalo que la cubra entera,
  // se usa el más grueso disponible.
  return INTERVALOS[INTERVALOS.length - 1].nombre;
}

interface Toque {
  resultado: "tp" | "sl";
}

/**
 * Revisa las velas de Binance desde que se publicó la señal hasta ahora
 * — no solo el precio actual — para saber si en algún momento el precio
 * tocó el take profit o el stop loss, aunque ya se haya alejado de ahí.
 *
 * Devuelve solo "tp" o "sl": el precio de cierre y el porcentaje los
 * calcula la propia base de datos desde la fila de la señal (migración
 * 019), para que no haya forma de inyectar un resultado inventado.
 */
async function buscarToqueTpSl(senal: Senal): Promise<Toque | null> {
  if (senal.take_profit == null && senal.stop_loss == null) return null;

  // Un par que no existe en Binance (ej. "BTC" en vez de "BTCUSDT", o el
  // ticker de una acción) nunca va a devolver velas. Se descarta antes de
  // gastar la request — y así tampoco se puede colar nada raro en la URL.
  const par = senal.par.trim().toUpperCase();
  if (!FORMATO_PAR_BINANCE.test(par)) return null;

  const desde = new Date(senal.created_at).getTime();
  if (!Number.isFinite(desde)) return null;

  const transcurrido = Math.max(0, Date.now() - desde);
  const intervalo = elegirIntervalo(transcurrido);

  try {
    const res = await fetch(
      `https://api.binance.com/api/v3/klines?symbol=${encodeURIComponent(par)}` +
        `&interval=${intervalo}&startTime=${desde}&limit=${MAX_VELAS}`,
      // Sin timeout explícito, fetch espera indefinidamente: una request
      // colgada a Binance dejaría la página de señales cargando para
      // siempre (y, con el candado de abajo, a todas las demás también).
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );
    if (!res.ok) return null;

    const velas = (await res.json()) as unknown;
    if (!Array.isArray(velas)) return null;

    for (const velaRaw of velas) {
      if (!Array.isArray(velaRaw)) continue;
      const high = parseFloat(String(velaRaw[2]));
      const low = parseFloat(String(velaRaw[3]));
      if (!Number.isFinite(high) || !Number.isFinite(low)) continue;

      // Dentro de UNA vela solo se conocen el máximo y el mínimo, no en
      // qué orden ocurrieron: si la vela tocó los dos niveles, es
      // imposible saber cuál llegó primero. Se revisa el stop loss antes
      // que el take profit a propósito — el resultado conservador. Darlo
      // por ganado sería inflar sistemáticamente el historial público de
      // señales, que es justo lo que da o quita credibilidad al producto.
      if (senal.tipo === "compra") {
        if (senal.stop_loss != null && low <= senal.stop_loss) {
          return { resultado: "sl" };
        }
        if (senal.take_profit != null && high >= senal.take_profit) {
          return { resultado: "tp" };
        }
      } else {
        if (senal.stop_loss != null && high >= senal.stop_loss) {
          return { resultado: "sl" };
        }
        if (senal.take_profit != null && low <= senal.take_profit) {
          return { resultado: "tp" };
        }
      }
    }
  } catch {
    return null;
  }

  return null;
}

/**
 * Evita martillar la API de Binance. El chequeo se dispara en cada carga
 * de /senales y encima la página se auto-refresca cada 45s, así que con
 * varias pestañas abiertas (y una request por señal activa) se puede
 * llegar rápido al límite de peticiones de Binance, que responde 418/429
 * y deja de cerrar señales justo cuando más hace falta.
 */
const PAUSA_MINIMA_MS = 30_000;
let ultimaRevision = 0;
let revisionEnCurso: Promise<void> | null = null;

/**
 * Revisa todas las señales activas y cierra automáticamente las que
 * tocaron TP o SL desde que se publicaron. Se llama al cargar /senales
 * (y con el auto-refresh de la página) — no es un cron 24/7 real, así
 * que si nadie visita la página por un buen rato, el cierre se aplica
 * en la próxima visita (usando igual las velas históricas, no el precio
 * del momento, así que el resultado sigue siendo correcto).
 */
export async function revisarYCerrarSenalesActivas(): Promise<void> {
  // Si ya hay una revisión corriendo, esta request NO la espera: sigue de
  // largo y pinta la página. Dos visitantes cargando /senales a la vez
  // duplicaban todas las llamadas a Binance, pero hacer que el segundo
  // espere al primero sería peor — encadenaría el tiempo de carga de una
  // request al de otra, y si la primera se cuelga, se cuelgan todas.
  if (revisionEnCurso) return;
  if (Date.now() - ultimaRevision < PAUSA_MINIMA_MS) return;

  revisionEnCurso = (async () => {
    try {
      // Nada de lo que pase aquí dentro debe tumbar el render de /senales:
      // es una tarea de mantenimiento en segundo plano, no el contenido de
      // la página. Si Binance o la base fallan, la señal simplemente se
      // cierra en la próxima visita.
      const supabase = await crearClienteSupabaseServidor();

      const { data: activas } = await supabase
        .from("senales")
        .select("*")
        .eq("estado", "activa")
        .is("resultado", null)
        .returns<Senal[]>();

      if (!activas || activas.length === 0) return;

      // En paralelo, no una tras otra: con N señales activas la versión
      // secuencial sumaba N latencias de red al render del Server
      // Component antes de mostrar nada.
      const toques = await Promise.all(
        activas.map((senal) =>
          buscarToqueTpSl(senal).catch(() => null)
        )
      );

      const secreto = obtenerSecretoServidor();

      await Promise.allSettled(
        activas.map((senal, i) => {
          const toque = toques[i];
          if (!toque) return null;
          // La función de Postgres recalcula precio de cierre y
          // porcentaje desde la propia señal (migración 019) — desde aquí
          // solo se le dice si tocó TP o SL.
          return supabase.rpc("cerrar_senal_automatica", {
            p_senal_id: senal.id,
            p_resultado: toque.resultado,
            p_secreto: secreto,
          });
        })
      );
    } catch (e) {
      console.error("[senales] falló la revisión automática de TP/SL:", e);
    } finally {
      ultimaRevision = Date.now();
      revisionEnCurso = null;
    }
  })();

  return revisionEnCurso;
}
