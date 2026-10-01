import { formatearDinero } from "@/lib/format";
import type { Diccionario } from "@/lib/i18n";

interface TarjetaTotalGanadoProps {
  monto: number;
  idCorto: number | null;
  t: Diccionario;
}

// Antes era una caja verde plana ("fondo de ganancia"); a pedido del
// dueño del proyecto se rediseñó como una tarjeta de crédito/débito —
// chip, número enmascarado con el id_corto del usuario, marca Trade4U.
export function TarjetaTotalGanado({ monto, idCorto, t }: TarjetaTotalGanadoProps) {
  // A 32px fijos el monto se salía de la tarjeta en pantallas angostas
  // (overflow-hidden lo cortaba sin aviso: "+$98,777,777.7") o se partía en
  // dos líneas. Se limita a lo que entra en el ancho real de la tarjeta
  // (cqw, la tarjeta es container) según la cantidad de caracteres:
  // ~0.66em por carácter en la fuente del monto.
  const textoMonto = `${monto > 0 ? "+" : ""}$${formatearDinero(monto)}`;
  const tamanoMonto = `min(32px, ${(100 / (0.66 * textoMonto.length)).toFixed(2)}cqw)`;

  // El id_corto real tiene 6 dígitos (100145...), así que el último grupo
  // es más largo que en una tarjeta de verdad; en pantallas de <360px el
  // número completo no entraba junto a la marca y saltaba de línea, por eso
  // el primer grupo de puntos se oculta ahí.
  const ultimoGrupo = idCorto ? String(idCorto).padStart(4, "0") : "••••";

  return (
    <div
      className="relative overflow-hidden rounded-2xl mb-3"
      style={{
        padding: "20px 22px 16px",
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
          width: 220,
          height: 220,
          top: -90,
          right: -60,
          background: "radial-gradient(circle, rgba(245,166,35,0.38), transparent 70%)",
          filter: "blur(6px)",
        }}
      />
      <div
        className="absolute rounded-full pointer-events-none"
        style={{
          width: 190,
          height: 190,
          bottom: -80,
          left: -50,
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
            width: 36,
            height: 27,
            background: "linear-gradient(135deg, #f6d892, #c9a227 55%, #8a6c1a)",
            boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.25)",
          }}
        >
          <div
            className="absolute"
            style={{ left: 6, right: 6, top: 9, height: 1, background: "rgba(0,0,0,0.25)" }}
          />
          <div
            className="absolute"
            style={{ left: 6, right: 6, top: 17, height: 1, background: "rgba(0,0,0,0.25)" }}
          />
        </div>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true" style={{ opacity: 0.75 }}>
          <path d="M8 10a6 6 0 0 1 8 0" stroke="#f4f5f7" strokeWidth="1.6" strokeLinecap="round" />
          <path d="M5.5 7.5a9.5 9.5 0 0 1 13 0" stroke="#f4f5f7" strokeWidth="1.6" strokeLinecap="round" opacity="0.6" />
          <circle cx="12" cy="14.5" r="1.4" fill="#f4f5f7" />
        </svg>
      </div>

      <div
        className="relative text-[11px] font-bold uppercase mt-4"
        style={{ zIndex: 1, letterSpacing: "0.14em", color: "rgba(244,245,247,0.58)" }}
      >
        {t.perfil.totalGanado}
      </div>
      <div
        className="relative font-display font-bold tabular mt-1"
        style={{
          zIndex: 1,
          fontSize: tamanoMonto,
          lineHeight: 1.15,
          color: "#eafff3",
          whiteSpace: "nowrap",
        }}
      >
        {monto > 0 && <span style={{ color: "#35e58f" }}>+</span>}
        {textoMonto.replace(/^\+/, "")}
      </div>

      <div className="relative flex items-end justify-between gap-3 mt-4.5" style={{ zIndex: 1 }}>
        <div
          className="font-mono whitespace-nowrap"
          style={{ fontSize: 12.5, letterSpacing: "0.07em", color: "rgba(244,245,247,0.5)" }}
        >
          <span className="hidden min-[360px]:inline">•••• </span>
          •••• •••• {ultimoGrupo}
        </div>
        <div className="font-display font-bold whitespace-nowrap" style={{ fontSize: 13, color: "rgba(244,245,247,0.92)" }}>
          Trade<span style={{ color: "#f5a623" }}>4U</span>
        </div>
      </div>
    </div>
  );
}
