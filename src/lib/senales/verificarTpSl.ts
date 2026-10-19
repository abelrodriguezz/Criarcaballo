import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerSecretoServidor } from "@/lib/supabase/secretoServidor";
import type { Senal } from "@/lib/types";

// Las velas se consultan a MEXC, no a Binance: Binance bloquea con 451 a
// cualquier servidor con IP en EE.UU./Europa, y Cloudflare Workers no deja
// fijar una región (corre en el borde más cercano a quien dispara el
// cron/la visita) — confirmado con una señal de prueba real que nunca se
// cerró porque Binance no respondía desde el Worker. MEXC no bloquea por
// región (ya se usa para los precios de /mercado por el mismo motivo) y
// su formato de velas es casi idéntico al de Binance.

/** Solo un par con este formato se puede consultar en la API de MEXC. */
const FORMATO_PAR = /^[A-Z0-9]{5,20}$/;

/** Máximo de velas que MEXC devuelve en una sola request (Binance da 1000). */
const MAX_VELAS = 500;

/**
 * Intervalos de vela de MEXC, de más fino a más grueso, con cuántos
 * minutos cubre cada uno en una sola request de MAX_VELAS velas.
 * Se elige el más fino que alcance a cubrir todo el tiempo que la señal
 * lleva activa — si se eligiera uno demasiado fino, las velas se
 * acabarían antes de llegar a "ahora" y un toque de TP/SL reciente
 * pasaría desapercibido para siempre.
 *
 * Los nombres de intervalo de MEXC no son los mismos que los de Binance:
 * "60m" en vez de "1h", "1W" (mayúscula) en vez de "1w".
 */
const INTERVALOS: ReadonlyArray<{ nombre: string; minutosPorVela: number }> = [
  { nombre: "1m", minutosPorVela: 1 },
  { nombre: "5m", minutosPorVela: 5 },
  { nombre: "15m", minutosPorVela: 15 },
  { nombre: "30m", minutosPorVela: 30 },
  { nombre: "60m", minutosPorVela: 60 },
  { nombre: "4h", minutosPorVela: 240 },
  { nombre: "1d", minutosPorVela: 1440 },
  { nombre: "1W", minutosPorVela: 10080 },
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
  /** Apertura de la vela que tocó el nivel (ISO): la fecha real del cierre. */
  tocadoEn: string | null;
}

/**
 * Revisa las velas de MEXC desde que se publicó la señal hasta ahora
 * — no solo el precio actual — para saber si en algún momento el precio
 * tocó el take profit o el stop loss, aunque ya se haya alejado de ahí.
 *
 * Devuelve solo "tp" o "sl": el precio de cierre y el porcentaje los
 * calcula la propia base de datos desde la fila de la señal (migración
 * 019), para que no haya forma de inyectar un resultado inventado.
 */
async function buscarToqueTpSl(senal: Senal): Promise<Toque | null> {
  if (senal.take_profit == null && senal.stop_loss == null) return null;

  // Un par que no existe en MEXC (ej. "BTC" en vez de "BTCUSDT", o el
  // ticker de una acción) nunca va a devolver velas. Se descarta antes de
  // gastar la request — y así tampoco se puede colar nada raro en la URL.
  const par = senal.par.trim().toUpperCase();
  if (!FORMATO_PAR.test(par)) return null;

  const desde = new Date(senal.created_at).getTime();
  if (!Number.isFinite(desde)) return null;

  const transcurrido = Math.max(0, Date.now() - desde);
  const intervalo = elegirIntervalo(transcurrido);

  try {
    // MEXC, a diferencia de Binance, solo respeta "startTime" como límite
    // inferior real si también se manda "endTime" — sin él, ignora
    // startTime y devuelve las últimas velas hasta ahora nada más (se
    // confirmó probando contra la API real), lo que haría pasar por alto
    // un toque de TP/SL viejo en una señal que lleva activa un buen rato.
    const ahora = Date.now();
    const res = await fetch(
      `https://api.mexc.com/api/v3/klines?symbol=${encodeURIComponent(par)}` +
        `&interval=${intervalo}&startTime=${desde}&endTime=${ahora}&limit=${MAX_VELAS}`,
      // Sin timeout explícito, fetch espera indefinidamente: una request
      // colgada a MEXC dejaría la página de señales cargando para
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
      const aperturaMs = Number(velaRaw[0]);
      const tocadoEn = Number.isFinite(aperturaMs)
        ? new Date(aperturaMs).toISOString()
        : null;

      // Dentro de UNA vela solo se conocen el máximo y el mínimo, no en
      // qué orden ocurrieron: si la vela tocó los dos niveles, es
      // imposible saber cuál llegó primero. Se revisa el stop loss antes
      // que el take profit a propósito — el resultado conservador. Darlo
      // por ganado sería inflar sistemáticamente el historial público de
      // señales, que es justo lo que da o quita credibilidad al producto.
      if (senal.tipo === "compra") {
        if (senal.stop_loss != null && low <= senal.stop_loss) {
          return { resultado: "sl", tocadoEn };
        }
        if (senal.take_profit != null && high >= senal.take_profit) {
          return { resultado: "tp", tocadoEn };
        }
      } else {
        if (senal.stop_loss != null && high >= senal.stop_loss) {
          return { resultado: "sl", tocadoEn };
        }
        if (senal.take_profit != null && low <= senal.take_profit) {
          return { resultado: "tp", tocadoEn };
        }
      }
    }
  } catch {
    return null;
  }

  return null;
}

/**
 * Evita martillar la API de MEXC. El chequeo se dispara en cada carga
 * de /senales y encima la página se auto-refresca cada 45s, así que con
 * varias pestañas abiertas (y una request por señal activa) se puede
 * llegar rápido al límite de peticiones de MEXC, que respondería con un
 * error y dejaría de cerrar señales justo cuando más hace falta.
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
  // duplicaban todas las llamadas a MEXC, pero hacer que el segundo
  // espere al primero sería peor — encadenaría el tiempo de carga de una
  // request al de otra, y si la primera se cuelga, se cuelgan todas.
  if (revisionEnCurso) return;
  if (Date.now() - ultimaRevision < PAUSA_MINIMA_MS) return;

  revisionEnCurso = (async () => {
    try {
      // Nada de lo que pase aquí dentro debe tumbar el render de /senales:
      // es una tarea de mantenimiento en segundo plano, no el contenido de
      // la página. Si MEXC o la base fallan, la señal simplemente se
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
          // solo se le dice si tocó TP o SL, y en qué vela (migración 067:
          // sin esto, cerrado_en quedaba con la hora de la visita a la
          // página, que puede ser horas o días después del toque real).
          return supabase.rpc("cerrar_senal_automatica", {
            p_senal_id: senal.id,
            p_resultado: toque.resultado,
            p_secreto: secreto,
            p_tocado_en: toque.tocadoEn,
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
