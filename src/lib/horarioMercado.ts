// Horario de la Bolsa de Nueva York (NYSE): lunes a viernes, 9:30am-4:00pm
// hora de Nueva York. Usa Intl con timeZone explícito para que el cálculo
// sea correcto sin importar en qué huso horario corra el servidor, y para
// que el horario de verano (EST/EDT) se ajuste solo.
const ZONA_NY = "America/New_York";

export function estaAbiertaBolsaNY(fecha: Date = new Date()): boolean {
  const partes = new Intl.DateTimeFormat("en-US", {
    timeZone: ZONA_NY,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(fecha);

  const mapa: Record<string, string> = {};
  for (const p of partes) mapa[p.type] = p.value;

  if (mapa.weekday === "Sat" || mapa.weekday === "Sun") return false;

  const horas = parseInt(mapa.hour, 10) % 24; // Intl a veces da "24" para medianoche
  const minutos = parseInt(mapa.minute, 10);
  const minutosDelDia = horas * 60 + minutos;

  const apertura = 9 * 60 + 30; // 9:30am
  const cierre = 16 * 60; // 4:00pm

  return minutosDelDia >= apertura && minutosDelDia < cierre;
}

/**
 * Cuánto se desvía Nueva York de UTC en ese instante, en milisegundos
 * (negativo: NY va detrás). Se calcula con Intl en vez de hardcodear -5/-4
 * para que el horario de verano se ajuste solo.
 */
function desfaseNYms(instante: number): number {
  const partes = new Intl.DateTimeFormat("en-US", {
    timeZone: ZONA_NY,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(new Date(instante));

  const mapa: Record<string, string> = {};
  for (const p of partes) mapa[p.type] = p.value;

  const comoSiFueraUTC = Date.UTC(
    Number(mapa.year),
    Number(mapa.month) - 1,
    Number(mapa.day),
    Number(mapa.hour) % 24, // Intl a veces da "24" para medianoche
    Number(mapa.minute),
    Number(mapa.second)
  );

  return comoSiFueraUTC - instante;
}

/**
 * Convierte una fecha "YYYY-MM-DD" en el instante exacto en que empieza
 * ese día en Nueva York.
 *
 * Por qué hace falta: los reportes usaban `${fecha}T00:00:00.000Z`, es
 * decir el día en UTC. Para un producto atado al horario de la bolsa de
 * Nueva York (y usado desde República Dominicana, UTC-4) eso significa
 * que una operación abierta a las 8 o 9 de la noche hora de NY caía en el
 * reporte del día SIGUIENTE — y esos reportes son los que deciden a quién
 * se le paga el premio del concurso.
 *
 * Se calcula en dos pasadas porque el desfase depende del instante, y el
 * instante es justo lo que se está buscando (importa solo los dos días al
 * año en que cambia el horario de verano).
 */
export function inicioDelDiaNY(fechaISO: string): Date {
  const aproximado = Date.parse(`${fechaISO}T00:00:00Z`);
  if (Number.isNaN(aproximado)) return new Date(NaN);

  const primeraPasada = aproximado - desfaseNYms(aproximado);
  return new Date(aproximado - desfaseNYms(primeraPasada));
}

/** Instante en que TERMINA ese día en Nueva York (exclusivo). */
export function finDelDiaNY(fechaISO: string): Date {
  const inicio = inicioDelDiaNY(fechaISO);
  if (Number.isNaN(inicio.getTime())) return inicio;

  // +26h y volver a anclar al inicio del día siguiente cubre bien los días
  // de 23 y 25 horas del cambio de horario.
  const siguiente = new Date(inicio.getTime() + 26 * 60 * 60 * 1000);
  return inicioDelDiaNY(fechaEnNY(siguiente));
}

/** La fecha "YYYY-MM-DD" que es en Nueva York en ese instante. */
export function fechaEnNY(fecha: Date = new Date()): string {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: ZONA_NY,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(fecha);
  return partes; // en-CA ya formatea como YYYY-MM-DD
}
