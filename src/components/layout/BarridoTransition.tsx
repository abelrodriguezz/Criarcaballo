"use client";

import { useEffect, useRef, useState, type ReactNode, type CSSProperties } from "react";
import { usePathname } from "next/navigation";

const ALTURAS_VELAS = [35, 60, 30, 75, 45, 55];

export function BarridoTransition({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const prevPathname = useRef(pathname);
  const franjaRef = useRef<HTMLDivElement>(null);

  const [mostrado, setMostrado] = useState(children);
  const [fase, setFase] = useState<"idle" | "saliendo" | "entrando">("idle");

  useEffect(() => {
    if (prevPathname.current === pathname) {
      // Mismo path (ej. la data del servidor se refrescó): actualiza sin animar.
      setMostrado(children);
      return;
    }
    prevPathname.current = pathname;

    const franja = franjaRef.current;
    if (franja) {
      franja.classList.remove("animar");
      // Fuerza el reflow para poder reiniciar la animación si se navega rápido varias veces.
      void franja.offsetWidth;
      franja.classList.add("animar");
    }

    setFase("saliendo");

    const cambiarContenido = setTimeout(() => {
      setMostrado(children);
      setFase("entrando");
    }, 380);

    const terminarTransicion = setTimeout(() => setFase("idle"), 900);

    return () => {
      clearTimeout(cambiarContenido);
      clearTimeout(terminarTransicion);
    };
  }, [pathname, children]);

  const claseFase =
    fase === "saliendo"
      ? "panel-saliendo"
      : fase === "entrando"
        ? "panel-entrando"
        : "";

  return (
    <div className="relative overflow-hidden">
      <div className="barrido-contenedor" aria-hidden="true">
        <div ref={franjaRef} className="barrido-franja">
          {ALTURAS_VELAS.map((altura, i) => (
            <div
              key={i}
              className="barrido-vela"
              style={
                {
                  "--h": `${altura}px`,
                  animationDelay: `${i * 0.05}s`,
                } as CSSProperties
              }
            />
          ))}
        </div>
      </div>
      <div className={claseFase}>{mostrado}</div>
    </div>
  );
}
