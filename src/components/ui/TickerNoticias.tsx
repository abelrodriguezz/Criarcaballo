import Link from "next/link";
import { urlSeguraParaEnlace } from "@/lib/url";

export interface ItemTicker {
  id: string;
  titulo: string;
  url: string;
  externo?: boolean;
  destacada?: boolean;
}

/**
 * Cinta de noticias corrida (estilo ticker de bolsa) para la portada.
 * La lista se duplica una vez para que el loop de la animación no se
 * note el salto — se pausa al pasar el mouse para poder leer/hacer clic.
 */
export function TickerNoticias({ items }: { items: ItemTicker[] }) {
  // El título viene de la base (lo escribe el admin) o del RSS de un medio
  // externo; la URL, de los mismos dos sitios. React ya escapa el texto,
  // pero un href con "javascript:" sí se ejecutaría: se descarta el enlace
  // entero si su URL no es http/https o una ruta interna.
  const seguros = items
    .map((n) => ({ ...n, url: urlSeguraParaEnlace(n.url) }))
    .filter((n): n is ItemTicker & { url: string } => n.url !== null);

  if (seguros.length === 0) return null;

  const dobles = [...seguros, ...seguros];

  return (
    <div className="border border-[var(--border)] rounded-2xl bg-surface overflow-hidden flex items-stretch">
      <div className="shrink-0 bg-brand-secondary text-white text-[11px] font-bold uppercase tracking-wide px-3.5 flex items-center gap-1.5 z-10">
        <span className="w-1.5 h-1.5 rounded-full bg-white animate-pulse" />
        Noticias
      </div>
      <div className="overflow-hidden flex-1 py-3">
        <div className="ticker-pista flex w-max gap-10 px-6">
          {dobles.map((n, i) => (
            <Link
              key={`${n.id}-${i}`}
              href={n.url}
              target="_blank"
              rel="noopener noreferrer"
              className="shrink-0 flex items-center gap-2.5 text-sm font-medium whitespace-nowrap hover:text-brand-primary transition-colors"
            >
              {n.destacada && <span className="text-brand-secondary">★</span>}
              {n.titulo}
              <span className="text-[var(--border)]">●</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
