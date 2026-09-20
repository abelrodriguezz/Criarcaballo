"use client";

import { useEffect, useState } from "react";

export function ThemeToggle() {
  const [esOscuro, setEsOscuro] = useState(false);

  useEffect(() => {
    // El tema real ya se aplicó al <html> antes de pintar (ver el script
    // inline en layout.tsx), así que aquí solo sincronizamos el ícono del
    // botón con lo que ya quedó puesto — es una lectura de un sistema
    // externo (localStorage/preferencia del SO) tras montar, el patrón
    // estándar para evitar un hydration mismatch entre servidor y cliente.
    const guardado = localStorage.getItem("trade4u-theme");
    const prefiereOscuro =
      guardado === "dark" ||
      (!guardado &&
        window.matchMedia("(prefers-color-scheme: dark)").matches);

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
    localStorage.setItem("trade4u-theme", nuevoValor ? "dark" : "light");
  }

  return (
    <button
      onClick={alternar}
      aria-label={esOscuro ? "Cambiar a modo claro" : "Cambiar a modo oscuro"}
      className="w-9 h-9 flex items-center justify-center rounded-full border border-[var(--border)] hover:bg-[var(--surface-hover)] transition-colors"
    >
      {esOscuro ? "☀️" : "🌙"}
    </button>
  );
}
