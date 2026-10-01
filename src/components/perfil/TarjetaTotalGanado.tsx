"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { formatearDinero } from "@/lib/format";
import { compartirImagenTarjeta } from "@/lib/compartirTarjetaGanancia";
import type { Diccionario } from "@/lib/i18n";

interface TarjetaTotalGanadoProps {
  monto: number;
  idCorto: number | null;
  t: Diccionario;
}

// Un solo cuerpo de tarjeta para las dos versiones (normal y expandida en
// pantalla completa): `escala` multiplica cada medida en vez de mantener
// dos copias del marcado que se puedan desincronizar.
function CuerpoTarjeta({ monto, idCorto, t, escala }: TarjetaTotalGanadoProps & { escala: number }) {
  // A 32px fijos el monto se salía de la tarjeta en pantallas angostas
  // (overflow-hidden lo cortaba sin aviso: "+$98,777,777.7") o se partía en
  // dos líneas. Se limita a lo que entra en el ancho real de la tarjeta
  // (cqw, la tarjeta es container) según la cantidad de caracteres:
  // ~0.66em por carácter en la fuente del monto.
  const textoMonto = `${monto > 0 ? "+" : ""}$${formatearDinero(monto)}`;
  const capMonto = 32 * escala;
  const tamanoMonto = `min(${capMonto}px, ${(100 / (0.66 * textoMonto.length)).toFixed(2)}cqw)`;

  // El id_corto real tiene 6 dígitos (100145...), así que el último grupo
  // es más largo que en una tarjeta de verdad y "•••• •••• •••• 100145" +
  // la marca no entran en todos los anchos. Antes se ocultaba el primer
  // grupo con un breakpoint de VIEWPORT (<360px), pero eso no sirve para la
  // versión agrandada (escala 1.7): ahí la fila medía ~400px dentro de una
  // tarjeta de ~250px y "Trade4U" quedaba fuera, cortado por overflow-hidden.
  // Ahora la fila se adapta al ancho real de la tarjeta:
  //  - los grupos de puntos van en un flex row-reverse + wrap con alto de
  //    una sola línea: los que no caben saltan a una 2a línea invisible,
  //    siempre grupos enteros y siempre los de más a la izquierda;
  //  - la letra se limita (cqw) para que al menos "•••• <id>" + la marca
  //    entren completos aun en la tarjeta más angosta.
  const ultimoGrupo = idCorto ? String(idCorto).padStart(4, "0") : "••••";
  // Ancho en em (de la letra del número) de "•••• <id>" + la marca: 0.67em
  // por carácter mono (0.6 + 0.07 de letter-spacing) y ~4.2em la marca
  // (que va a 13/12.5 del tamaño del número). 12px de gap entre ambos.
  const emMinimos = (5 + ultimoGrupo.length) * 0.67 + 4.2;
  const tamanoNumero = `min(${12.5 * escala}px, calc((100cqw - 12px) / ${emMinimos.toFixed(2)}))`;
  const tamanoMarca = `calc(${tamanoNumero} * 1.04)`;

  return (
    <div
      className="relative overflow-hidden rounded-2xl"
      style={{
        // El relleno lateral NO crece con toda la escala: a 1.7 se comía
        // ~75px del ancho en un cel de 320px y el monto de la versión
        // agrandada quedaba casi del mismo tamaño que en la chica (el monto
        // se limita al ancho disponible, ver tamanoMonto).
        padding: `${20 * escala}px ${22 * Math.min(escala, 1.3)}px ${16 * escala}px`,
        background:
          "radial-gradient(120% 150% at 100% -10%, #2c3c58 0%, #141b2e 42%, #090c14 100%)",
        boxShadow:
          "0 18px 36px -14px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.07)",
        isolation: "isolate",
        containerType: "inline-size",
      }}
    >
      <div
        className="absolute rounded-full pointer-events-none"
        style={{
          width: 220 * escala,
          height: 220 * escala,
          top: -90 * escala,
          right: -60 * escala,
          background: "radial-gradient(circle, rgba(245,166,35,0.38), transparent 70%)",
          filter: "blur(6px)",
        }}
      />
      <div
        className="absolute rounded-full pointer-events-none"
        style={{
          width: 190 * escala,
          height: 190 * escala,
          bottom: -80 * escala,
          left: -50 * escala,
          background: "radial-gradient(circle, rgba(34,211,238,0.26), transparent 70%)",
          filter: "blur(6px)",
        }}
      />
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          zIndex: 2,
          background:
            "linear-gradient(115deg, transparent 42%, rgba(255,255,255,0.10) 52%, transparent 62%)",
        }}
      />

      <div className="relative flex items-start justify-between" style={{ zIndex: 1 }}>
        <div
          className="rounded-md relative"
          style={{
            width: 36 * escala,
            height: 27 * escala,
            background: "linear-gradient(135deg, #f6d892, #c9a227 55%, #8a6c1a)",
            boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.25)",
          }}
        >
          <div
            className="absolute"
            style={{ left: 6 * escala, right: 6 * escala, top: 9 * escala, height: 1, background: "rgba(0,0,0,0.25)" }}
          />
          <div
            className="absolute"
            style={{ left: 6 * escala, right: 6 * escala, top: 17 * escala, height: 1, background: "rgba(0,0,0,0.25)" }}
          />
        </div>
        <svg width={20 * escala} height={20 * escala} viewBox="0 0 24 24" fill="none" aria-hidden="true" style={{ opacity: 0.75 }}>
          <path d="M8 10a6 6 0 0 1 8 0" stroke="#f4f5f7" strokeWidth="1.6" strokeLinecap="round" />
          <path d="M5.5 7.5a9.5 9.5 0 0 1 13 0" stroke="#f4f5f7" strokeWidth="1.6" strokeLinecap="round" opacity="0.6" />
          <circle cx="12" cy="14.5" r="1.4" fill="#f4f5f7" />
        </svg>
      </div>

      <div
        className="relative font-bold uppercase"
        style={{ zIndex: 1, fontSize: 11 * escala, letterSpacing: "0.14em", color: "rgba(244,245,247,0.58)", marginTop: 16 * escala }}
      >
        {t.perfil.totalGanado}
      </div>
      <div
        className="relative font-display font-bold tabular"
        style={{
          zIndex: 1,
          fontSize: tamanoMonto,
          lineHeight: 1.15,
          color: "#eafff3",
          whiteSpace: "nowrap",
          marginTop: 4 * escala,
        }}
      >
        {monto > 0 && <span style={{ color: "#35e58f" }}>+</span>}
        {textoMonto.replace(/^\+/, "")}
      </div>

      <div className="relative flex items-end justify-between gap-3" style={{ zIndex: 1, marginTop: 18 * escala }}>
        <div
          className="font-mono flex flex-row-reverse flex-wrap justify-end overflow-hidden min-w-0 flex-1"
          style={{
            fontSize: tamanoNumero,
            lineHeight: 1.3,
            height: "1.3em",
            columnGap: "0.6em",
            letterSpacing: "0.07em",
            color: "rgba(244,245,247,0.5)",
          }}
        >
          {/* row-reverse: en el DOM van de derecha a izquierda; justify-end
              (= izquierda en row-reverse) deja el número alineado a la
              izquierda como en una tarjeta real. */}
          <span className="whitespace-nowrap">{ultimoGrupo}</span>
          <span className="whitespace-nowrap" aria-hidden="true">••••</span>
          <span className="whitespace-nowrap" aria-hidden="true">••••</span>
          <span className="whitespace-nowrap" aria-hidden="true">••••</span>
        </div>
        <div className="font-display font-bold whitespace-nowrap shrink-0" style={{ fontSize: tamanoMarca, color: "rgba(244,245,247,0.92)" }}>
          Trade<span style={{ color: "#f5a623" }}>4U</span>
        </div>
      </div>
    </div>
  );
}

// Antes era una caja verde plana ("fondo de ganancia"); a pedido del
// dueño del proyecto se rediseñó como una tarjeta de crédito/débito —
// chip, número enmascarado con el id_corto del usuario, marca Trade4U.
// Al tocarla (sobre todo pensado para el cel) se agranda a pantalla
// completa para leerla mejor; se cierra tocándola de nuevo, el fondo, la
// X o Esc.
// Duración de tarjeta-ganancia-saliendo (globals.css) — hay que esperarla
// antes de desmontar o el cierre se corta en seco a mitad de la animación.
const DURACION_CIERRE_MS = 350;

export function TarjetaTotalGanado(props: TarjetaTotalGanadoProps) {
  const { t } = props;
  const [expandida, setExpandida] = useState(false);
  const [cerrando, setCerrando] = useState(false);
  const [compartiendo, setCompartiendo] = useState(false);
  const [errorCompartir, setErrorCompartir] = useState(false);
  const botonAbrir = useRef<HTMLButtonElement>(null);
  const botonCerrar = useRef<HTMLButtonElement>(null);

  async function compartir() {
    setErrorCompartir(false);
    setCompartiendo(true);
    try {
      await compartirImagenTarjeta({
        monto: props.monto,
        idCorto: props.idCorto,
        etiqueta: t.perfil.totalGanado,
        formatearDinero,
      });
    } catch (e) {
      // AbortError: la persona cerró el panel nativo de compartir sin
      // elegir nada -- cancelar no es un error, no hay nada que avisar.
      if (e instanceof DOMException && e.name === "AbortError") {
        // no-op
      } else {
        setErrorCompartir(true);
      }
    } finally {
      setCompartiendo(false);
    }
  }

  function abrir() {
    setCerrando(false);
    setExpandida(true);
  }

  // useCallback: referencia estable para poder listarla en las deps del
  // efecto de abajo sin que el listener de Escape quede con una versión
  // vieja de la función ni se tenga que reinstalar en cada render.
  const cerrar = useCallback(() => {
    // No se desmonta de una: primero corre la animación de salida
    // (tarjeta-ganancia-saliendo) y recién al terminar se quita del DOM.
    setCerrando(true);
    window.setTimeout(() => {
      setExpandida(false);
      setCerrando(false);
    }, DURACION_CIERRE_MS);
  }, []);

  useEffect(() => {
    if (!expandida) return;
    const overflowOriginal = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    // Foco a la X al abrir (teclado/lector de pantalla) y de vuelta a la
    // tarjeta chica al cerrar, en vez de dejarlo perdido en el <body>.
    botonCerrar.current?.focus();
    const abrir = botonAbrir.current;
    function alSoltarTecla(e: KeyboardEvent) {
      if (e.key === "Escape") cerrar();
    }
    window.addEventListener("keydown", alSoltarTecla);
    return () => {
      document.body.style.overflow = overflowOriginal;
      window.removeEventListener("keydown", alSoltarTecla);
      abrir?.focus({ preventScroll: true });
    };
  }, [expandida, cerrar]);

  return (
    <>
      <button
        ref={botonAbrir}
        type="button"
        onClick={abrir}
        aria-haspopup="dialog"
        aria-expanded={expandida}
        className="w-full text-left appearance-none bg-transparent border-0 p-0 m-0 mb-3 block cursor-pointer"
      >
        {/* Sin aria-label en el botón: taparía el monto para los lectores
            de pantalla; la acción va como texto oculto al final. */}
        <CuerpoTarjeta {...props} escala={1} />
        <span className="sr-only">{t.perfil.agrandarTarjeta}</span>
      </button>

      {expandida && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={t.perfil.totalGanado}
          className={`fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-black/80 backdrop-blur-sm ${
            cerrando ? "overlay-ganancia-saliendo" : "overlay-ganancia-entrando"
          }`}
          onClick={cerrar}
        >
          <div
            className={`relative w-full max-w-[380px] ${
              cerrando ? "tarjeta-ganancia-saliendo" : "tarjeta-ganancia-entrando"
            }`}
            style={{ transformStyle: "preserve-3d" }}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              ref={botonCerrar}
              type="button"
              onClick={cerrar}
              aria-label={t.perfil.cerrarTarjeta}
              className="absolute -top-3 -right-3 z-10 w-9 h-9 rounded-full bg-surface border border-[var(--border)] flex items-center justify-center text-foreground shadow-lg"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M6 6l12 12M18 6L6 18" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
              </svg>
            </button>
            <button
              type="button"
              onClick={compartir}
              disabled={compartiendo}
              aria-label={t.perfil.compartirGanancia}
              className="absolute -top-3 -left-3 z-10 w-9 h-9 rounded-full bg-surface border border-[var(--border)] flex items-center justify-center text-foreground shadow-lg disabled:opacity-60"
            >
              {compartiendo ? (
                <span className="block w-3.5 h-3.5 rounded-full border-2 border-foreground-muted border-t-transparent animate-spin" />
              ) : (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path d="M12 16V4M12 4l-4 4M12 4l4 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                  <path d="M4 14v4a2 2 0 002 2h12a2 2 0 002-2v-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>
            <button
              type="button"
              onClick={cerrar}
              className="w-full text-left appearance-none bg-transparent border-0 p-0 m-0 block cursor-pointer"
            >
              <CuerpoTarjeta {...props} escala={1.7} />
              <span className="sr-only">{t.perfil.cerrarTarjeta}</span>
            </button>
            {errorCompartir && (
              <p className="absolute left-0 right-0 -bottom-7 text-center text-[12px] text-loss">
                {t.perfil.errorCompartir}
              </p>
            )}
          </div>
        </div>
      )}
    </>
  );
}
