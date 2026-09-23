/**
 * Export a .csv (no .xlsx binario) — Excel lo abre nativo con doble
 * clic, sin depender de ninguna librería pesada en el proyecto. Compartido
 * entre todos los botones "Exportar a Excel" del panel de admin, para no
 * duplicar la protección contra inyección de fórmulas en cada uno.
 */

const esNumero = (t: string) => /^-?\d+(\.\d+)?$/.test(t);

/**
 * Además de escapar las comillas, neutraliza la inyección de fórmulas:
 * Excel/LibreOffice interpretan como fórmula cualquier celda que empiece
 * por = + - @ (o tab/CR), así que un correo o nombre tipo =HYPERLINK(...)
 * podría ejecutar algo en la máquina del admin al abrir el archivo.
 * Anteponer un apóstrofo lo deja como texto plano sin cambiar lo que se
 * lee. Un número negativo ("-22.07") empieza por "-" pero es legítimo: se
 * deja pasar para que la columna siga siendo numérica en Excel.
 */
export function escaparCeldaCSV(v: string | number): string {
  const texto = String(v);
  const seguro =
    /^[=+\-@\t\r]/.test(texto) && !esNumero(texto) ? `'${texto}` : texto;
  return `"${seguro.replace(/"/g, '""')}"`;
}

/** Une una fila ya escapada con comas — usar siempre junto a escaparCeldaCSV. */
export function filaCSV(valores: (string | number)[]): string {
  return valores.map(escaparCeldaCSV).join(",");
}

/** El BOM al inicio es para que Excel detecte UTF-8 y no rompa acentos/ñ. */
export function descargarCSV(nombreArchivo: string, encabezados: string[], lineas: string[]) {
  const csv = [filaCSV(encabezados), ...lineas].join("\r\n");
  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nombreArchivo;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
