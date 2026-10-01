// Genera una imagen PNG de la tarjeta de ganancias (dibujada a mano en un
// <canvas>, no una captura de pantalla del DOM real) y la comparte con la
// Web Share API nativa (archivo, nunca texto/título/url — así WhatsApp y
// el resto de apps muestran solo la imagen). Se dibuja aparte en vez de
// capturar la tarjeta real para no depender de que html2canvas (u otra
// librería) sepa interpretar container queries/blur/gradientes exactamente
// igual que el navegador.

const ANCHO = 1000;
const ALTO = 580;
const ESCALA_EXPORT = 2; // nitidez en pantallas retina

interface DatosTarjetaCompartir {
  monto: number;
  idCorto: number | null;
  etiqueta: string; // ya traducida (t.perfil.totalGanado)
  formatearDinero: (valor: number) => string;
}

function trazarRectRedondeado(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** letter-spacing manual: fillText no lo soporta directo. */
function dibujarTextoEspaciado(
  ctx: CanvasRenderingContext2D,
  texto: string,
  x: number,
  y: number,
  espacio: number
) {
  let cursor = x;
  for (const char of texto) {
    ctx.fillText(char, cursor, y);
    cursor += ctx.measureText(char).width + espacio;
  }
}

async function dibujarTarjeta(ctx: CanvasRenderingContext2D, datos: DatosTarjetaCompartir) {
  // Las fuentes de next/font ya están en el documento, pero hay que
  // esperar a que el navegador termine de cargarlas antes de medir/dibujar
  // texto con ellas — si no, canvas dibuja con la fuente de respaldo y el
  // ajuste de tamaño del monto queda mal calculado.
  // document.fonts.ready solo espera las fuentes que YA se están bajando:
  // una cara que la página todavía no usó no se pide nunca y canvas
  // dibujaría con la de respaldo. Se piden explícitamente las que usa la
  // imagen (si falla alguna, se sigue con la de respaldo, no se aborta).
  if (document.fonts) {
    await Promise.all(
      [
        "700 24px 'Space Grotesk'",
        "700 32px 'Space Grotesk'",
        "700 92px 'JetBrains Mono'",
        "500 28px 'JetBrains Mono'",
      ].map((f) => document.fonts.load(f).catch(() => []))
    );
    await document.fonts.ready;
  }

  ctx.scale(ESCALA_EXPORT, ESCALA_EXPORT);

  trazarRectRedondeado(ctx, 0, 0, ANCHO, ALTO, 28);
  ctx.clip();

  const gradFondo = ctx.createRadialGradient(
    ANCHO * 0.95,
    -ALTO * 0.15,
    0,
    ANCHO * 0.4,
    ALTO * 0.5,
    ANCHO * 1.05
  );
  gradFondo.addColorStop(0, "#2c3c58");
  gradFondo.addColorStop(0.42, "#141b2e");
  gradFondo.addColorStop(1, "#090c14");
  ctx.fillStyle = gradFondo;
  ctx.fillRect(0, 0, ANCHO, ALTO);

  const glowAmbar = ctx.createRadialGradient(ANCHO - 50, -10, 0, ANCHO - 50, -10, 260);
  glowAmbar.addColorStop(0, "rgba(245,166,35,0.32)");
  glowAmbar.addColorStop(1, "rgba(245,166,35,0)");
  ctx.fillStyle = glowAmbar;
  ctx.fillRect(0, 0, ANCHO, ALTO);

  const glowCian = ctx.createRadialGradient(40, ALTO + 10, 0, 40, ALTO + 10, 230);
  glowCian.addColorStop(0, "rgba(34,211,238,0.22)");
  glowCian.addColorStop(1, "rgba(34,211,238,0)");
  ctx.fillStyle = glowCian;
  ctx.fillRect(0, 0, ANCHO, ALTO);

  // Brillo diagonal, como el shine de la tarjeta real.
  ctx.save();
  ctx.globalAlpha = 0.08;
  ctx.fillStyle = "#ffffff";
  ctx.translate(ANCHO * 0.58, ALTO * 0.5);
  ctx.rotate((-25 * Math.PI) / 180);
  ctx.fillRect(-90, -ALTO, 170, ALTO * 2);
  ctx.restore();

  // Chip
  const chipX = 56;
  const chipY = 56;
  const chipW = 86;
  const chipH = 64;
  const gradChip = ctx.createLinearGradient(chipX, chipY, chipX + chipW, chipY + chipH);
  gradChip.addColorStop(0, "#f6d892");
  gradChip.addColorStop(0.55, "#c9a227");
  gradChip.addColorStop(1, "#8a6c1a");
  trazarRectRedondeado(ctx, chipX, chipY, chipW, chipH, 12);
  ctx.fillStyle = gradChip;
  ctx.fill();
  ctx.strokeStyle = "rgba(0,0,0,0.25)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(chipX + 14, chipY + 22);
  ctx.lineTo(chipX + chipW - 14, chipY + 22);
  ctx.moveTo(chipX + 14, chipY + 42);
  ctx.lineTo(chipX + chipW - 14, chipY + 42);
  ctx.stroke();

  // Etiqueta
  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(244,245,247,0.6)";
  ctx.font = "700 24px 'Space Grotesk', sans-serif";
  dibujarTextoEspaciado(ctx, datos.etiqueta.toUpperCase(), 56, 192, 3);

  // Monto — se achica si no entra en el ancho disponible.
  const textoMonto = `${datos.monto > 0 ? "+" : ""}$${datos.formatearDinero(datos.monto)}`;
  let tamanoMonto = 92;
  ctx.font = `700 ${tamanoMonto}px 'JetBrains Mono', monospace`;
  const anchoDisponible = ANCHO - 112;
  while (ctx.measureText(textoMonto).width > anchoDisponible && tamanoMonto > 40) {
    tamanoMonto -= 4;
    ctx.font = `700 ${tamanoMonto}px 'JetBrains Mono', monospace`;
  }
  // El "+" en verde, igual que en la tarjeta en pantalla.
  if (textoMonto.startsWith("+")) {
    ctx.fillStyle = "#35e58f";
    ctx.fillText("+", 56, 300);
    ctx.fillStyle = "#eafff3";
    ctx.fillText(textoMonto.slice(1), 56 + ctx.measureText("+").width, 300);
  } else {
    ctx.fillStyle = "#eafff3";
    ctx.fillText(textoMonto, 56, 300);
  }

  // Número enmascarado + marca, abajo.
  const ultimoGrupo = datos.idCorto ? String(datos.idCorto).padStart(4, "0") : "••••";
  ctx.font = "500 28px 'JetBrains Mono', monospace";
  ctx.fillStyle = "rgba(244,245,247,0.5)";
  dibujarTextoEspaciado(ctx, `•••• •••• •••• ${ultimoGrupo}`, 56, ALTO - 64, 2);

  ctx.font = "700 32px 'Space Grotesk', sans-serif";
  const anchoTrade = ctx.measureText("Trade").width;
  const anchoMarca = anchoTrade + ctx.measureText("4U").width;
  const marcaX = ANCHO - 56 - anchoMarca;
  ctx.fillStyle = "rgba(244,245,247,0.92)";
  ctx.fillText("Trade", marcaX, ALTO - 64);
  ctx.fillStyle = "#f5a623";
  ctx.fillText("4U", marcaX + anchoTrade, ALTO - 64);
}

export async function generarImagenTarjeta(datos: DatosTarjetaCompartir): Promise<Blob> {
  const canvas = document.createElement("canvas");
  canvas.width = ANCHO * ESCALA_EXPORT;
  canvas.height = ALTO * ESCALA_EXPORT;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("No se pudo crear el contexto de canvas.");

  await dibujarTarjeta(ctx, datos);

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("No se pudo generar la imagen."));
    }, "image/png");
  });
}

const NOMBRE_ARCHIVO = "trade4u-ganancias.png";

/** Genera el PNG ya envuelto en un File listo para compartir. Conviene
 * llamarlo ANTES del toque en el botón (al abrir la tarjeta): ver
 * compartirArchivoTarjeta. */
export async function prepararArchivoTarjeta(datos: DatosTarjetaCompartir): Promise<File> {
  const blob = await generarImagenTarjeta(datos);
  return new File([blob], NOMBRE_ARCHIVO, { type: "image/png" });
}

function descargarArchivo(archivo: File) {
  const url = URL.createObjectURL(archivo);
  const enlace = document.createElement("a");
  enlace.href = url;
  enlace.download = NOMBRE_ARCHIVO;
  document.body.appendChild(enlace);
  enlace.click();
  enlace.remove();
  // Revocar en el mismo tick puede cancelar la descarga en algunos
  // navegadores (Safari/Firefox) — se le da un margen.
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/**
 * Comparte SOLO la imagen (sin título/texto/url -- así WhatsApp y el resto
 * de apps no agregan nada de texto). Si el navegador no soporta compartir
 * archivos (la mayoría de los de escritorio), descarga el PNG directo.
 *
 * navigator.share() exige "activación de usuario" vigente: Safari en iOS
 * la pierde si antes del share hubo trabajo asíncrono (cargar fuentes,
 * canvas.toBlob) y rechaza con NotAllowedError. Por eso el archivo se
 * prepara aparte (prepararArchivoTarjeta) y aquí se llama a share() sin
 * ningún await previo. Si aun así el navegador lo rechaza por eso, se
 * descarga el PNG en vez de mostrar un error.
 */
export async function compartirArchivoTarjeta(
  archivo: File
): Promise<"compartido" | "descargado"> {
  if (
    typeof navigator.canShare === "function" &&
    typeof navigator.share === "function" &&
    navigator.canShare({ files: [archivo] })
  ) {
    try {
      await navigator.share({ files: [archivo] });
      return "compartido";
    } catch (e) {
      // AbortError (la persona cerró el panel) se propaga: el componente
      // lo trata como no-op. NotAllowedError → descarga como respaldo.
      if (!(e instanceof DOMException && e.name === "NotAllowedError")) throw e;
    }
  }

  descargarArchivo(archivo);
  return "descargado";
}

export async function compartirImagenTarjeta(
  datos: DatosTarjetaCompartir
): Promise<"compartido" | "descargado"> {
  return compartirArchivoTarjeta(await prepararArchivoTarjeta(datos));
}
