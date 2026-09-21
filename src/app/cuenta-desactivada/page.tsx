import { CerrarSesionBoton } from "@/components/auth/CerrarSesionBoton";
import { obtenerDiccionario } from "@/lib/i18n/servidor";

export default async function PaginaCuentaDesactivada() {
  const t = await obtenerDiccionario();
  return (
    <div className="py-16">
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.cuentaDesactivada.titulo}
        </h1>
        <p className="text-sm text-foreground-muted mb-5">
          {t.cuentaDesactivada.texto}
        </p>
        <CerrarSesionBoton t={t} />
      </div>
    </div>
  );
}
