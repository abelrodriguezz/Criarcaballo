"use client";

import { useLayoutEffect, useReducer, useRef, useState, type ChangeEvent } from "react";

// Cédula dominicana: 3 dígitos, guion, 7 dígitos, guion, 1 dígito
// (001-1234567-8). El mismo formato se exige en la base de datos
// (migración 084, constraint usuarios_cedula_formato).
export const CEDULA_VALIDA = /^[0-9]{3}-[0-9]{7}-[0-9]$/;

/** Inserta los guiones automáticamente mientras se escribe, sin que la
 * persona tenga que teclearlos ella misma. */
export function formatearCedula(valor: string): string {
  const digitos = valor.replace(/\D/g, "").slice(0, 11);
  const p1 = digitos.slice(0, 3);
  const p2 = digitos.slice(3, 10);
  const p3 = digitos.slice(10, 11);
  if (digitos.length <= 3) return p1;
  if (digitos.length <= 10) return `${p1}-${p2}`;
  return `${p1}-${p2}-${p3}`;
}

/** Posición en el texto formateado justo después del dígito número
 * `cantDigitos` (contando desde 1). Sirve para devolver el cursor a donde
 * estaba después de reformatear, en vez de mandarlo siempre al final. */
function posicionTrasDigitos(formateado: string, cantDigitos: number): number {
  if (cantDigitos <= 0) return 0;
  let vistos = 0;
  for (let i = 0; i < formateado.length; i++) {
    if (/\d/.test(formateado[i]) && ++vistos === cantDigitos) return i + 1;
  }
  return formateado.length;
}

/**
 * Estado + manejador de un input de cédula con autoformato. Compartido por
 * el registro y por "Datos de contacto" en /perfil: antes /perfil tenía su
 * propia copia simplificada (solo formatearCedula en onChange) y volvía a
 * tener los dos bugs que ya se habían arreglado en el registro — el cursor
 * saltaba al final al editar un dígito del medio y Backspace justo después
 * de un guion no hacía nada (se quitaba el guion y el reformateo lo volvía
 * a poner).
 */
export function useCampoCedula(inicial: string) {
  const [cedula, setCedula] = useState(inicial);
  const inputRef = useRef<HTMLInputElement>(null);
  const cursorCedula = useRef<number | null>(null);
  const [renderCedula, forzarRenderCedula] = useReducer((n: number) => n + 1, 0);

  function alCambiarCedula(e: ChangeEvent<HTMLInputElement>) {
    const input = e.target;
    const crudo = input.value;
    const cursor = input.selectionStart ?? crudo.length;
    let digitos = crudo.replace(/\D/g, "");
    let digitosAntesDelCursor = crudo.slice(0, cursor).replace(/\D/g, "").length;

    const soloSeBorroUnGuion =
      crudo.length < cedula.length && digitos === cedula.replace(/\D/g, "");
    if (soloSeBorroUnGuion) {
      const tipo = (e.nativeEvent as InputEvent).inputType;
      if (tipo === "deleteContentBackward" && digitosAntesDelCursor > 0) {
        digitos =
          digitos.slice(0, digitosAntesDelCursor - 1) + digitos.slice(digitosAntesDelCursor);
        digitosAntesDelCursor -= 1;
      } else if (tipo === "deleteContentForward") {
        digitos =
          digitos.slice(0, digitosAntesDelCursor) + digitos.slice(digitosAntesDelCursor + 1);
      }
    }

    const formateado = formatearCedula(digitos);
    const nuevoCursor = posicionTrasDigitos(formateado, Math.min(digitosAntesDelCursor, 11));
    // El cursor se aplica en el useLayoutEffect de abajo, en el mismo commit
    // en que React escribe el valor (un requestAnimationFrame llegaba tarde
    // si se tecleaba rápido y mandaba los dígitos siguientes a otro lado).
    // Si el valor no cambia (ej. tecleó una letra) igual se fuerza un render
    // para que el efecto corra y el cursor no salte al final.
    cursorCedula.current = nuevoCursor;
    setCedula(formateado);
    if (formateado === cedula) forzarRenderCedula();
  }

  useLayoutEffect(() => {
    const pos = cursorCedula.current;
    const el = inputRef.current;
    cursorCedula.current = null;
    if (pos !== null && el && document.activeElement === el) el.setSelectionRange(pos, pos);
  }, [cedula, renderCedula]);

  return { cedula, setCedula, inputRef, alCambiarCedula };
}
