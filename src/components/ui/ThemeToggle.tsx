"use client";

import { useEffect, useState } from "react";

// Las etiquetas vienen del diccionario (NavBar): antes estaban fijas en
// español y un lector de pantalla las leía así con la app en inglés.
export function ThemeToggle({
  etiquetaClaro,
  etiquetaOscuro,
}: {
  etiquetaClaro: string;
  etiquetaOscuro: string;
}) {
  const [esOscuro, setEsOscuro] = useState(true);

  useEffect(() => {
    // El tema real ya se aplicó al <html> antes de pintar (ver el script
    // inline en layout.tsx), así que aquí solo sincronizamos el ícono del
    // botón con lo que ya quedó puesto — es una lectura de un sistema
    // externo (localStorage/preferencia del SO) tras montar, el patrón
    // estándar para evitar un hydration mismatch entre servidor y cliente.
    // Debe coincidir exactamente con la lógica del script inline de
    // layout.tsx: oscuro por defecto salvo que ya se haya elegido claro.
    // Si localStorage no está disponible (modo incógnito estricto, storage
    // bloqueado, etc.) esto lanzaría sin capturar y tumbaría toda la app a
    // la pantalla de error de Next para CUALQUIER visitante (el botón de
    // tema está en el NavBar de todas las páginas) — igual que ya se cuida
    // en el script inline de layout.tsx.
    let guardado: string | null = null;
    try {
      guardado = localStorage.getItem("trade4u-theme");
    } catch {
      // sin storage, seguimos con el valor por defecto (oscuro).
    }
    const prefiereOscuro = guardado ? guardado === "dark" : true;

    // eslint-disable-next-line react-hooks/set-state-in-effect
    setEsOscuro(prefiereOscuro);
  }, []);

  function alternar() {
    const nuevoValor = !esOscuro;
    setEsOscuro(nuevoValor);
    document.documentElement.setAttribute(
      "data-theme",
      nuevoValor ? "dark" : "light"
    );
    try {
      localStorage.setItem("trade4u-theme", nuevoValor ? "dark" : "light");
    } catch {
      // sin storage, el tema no persiste entre visitas pero el toggle
      // igual funciona en la sesión actual.
    }
  }

  return (
    <button
      onClick={alternar}
      aria-label={esOscuro ? etiquetaClaro : etiquetaOscuro}
      className="w-9 h-9 flex items-center justify-center rounded-full border border-[var(--border)] hover:bg-[var(--surface-hover)] transition-colors"
    >
      {esOscuro ? "☀️" : "🌙"}
    </button>
  );
}
