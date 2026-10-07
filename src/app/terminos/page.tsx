import Link from "next/link";
import { SECCIONES_TERMINOS } from "@/lib/legal/terminosYCondiciones";

export const metadata = {
  title: "Términos y Condiciones — Trade4U",
};

// Página pública a propósito (sin chequeo de sesión): tiene que poder
// abrirse desde Registro/Login, antes de que la persona tenga cuenta.
export default function PaginaTerminos() {
  return (
    <div className="py-10 max-w-[640px]">
      <Link
        href="/login"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Terms &amp; Conditions / Privacy Policy
      </h1>
      <p className="text-foreground-muted text-[13px] mb-7">
        Last reviewed: October 2026.
      </p>

      {SECCIONES_TERMINOS.map((seccion) => (
        <div key={seccion.numero} className="mb-5">
          <h2 className="font-display font-semibold text-[15px] mb-2">
            {seccion.numero}. {seccion.titulo}
          </h2>
          {seccion.contenido.map((parrafo, i) => (
            <p
              key={i}
              className="text-foreground-muted text-[14px] leading-relaxed mb-1.5"
            >
              {parrafo}
            </p>
          ))}
        </div>
      ))}
    </div>
  );
}
