import { IconoInfo } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import {
  obtenerConfigNosotros,
  obtenerConfigNosotrosCompleto,
} from "@/lib/config-nosotros";
import { AdminNosotrosForm } from "@/components/admin/AdminNosotrosForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaNosotros() {
  const [usuario, locale, t] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerLocale(),
    obtenerDiccionario(),
  ]);
  const usuarioEsAdmin = esAdmin(usuario);

  const [nosotros, nosotrosCompleto] = await Promise.all([
    obtenerConfigNosotros(locale),
    usuarioEsAdmin ? obtenerConfigNosotrosCompleto() : Promise.resolve(null),
  ]);

  return (
    <div className="py-10 max-w-[640px]">
      {usuarioEsAdmin && nosotrosCompleto && (
        <AdminNosotrosForm nosotrosActual={nosotrosCompleto} />
      )}

      <h1 className="font-display font-semibold text-[26px] mb-6">
        {nosotros.titulo}
      </h1>

      {nosotros.parrafos.map((parrafo, i) => (
        <p
          key={i}
          className="text-foreground-muted text-[15px] leading-relaxed mb-4"
        >
          {parrafo}
        </p>
      ))}

      <div className="border border-[var(--border)] bg-surface p-5 flex gap-3 mt-4">
        <IconoInfo className="w-4 h-4 shrink-0 mt-0.5 text-foreground-muted" />
        <div>
          <div className="font-semibold text-sm mb-1">
            {t.nosotros.disclaimerTitulo}
          </div>
          <p className="text-[13px] text-foreground-muted leading-relaxed">
            {t.nosotros.disclaimer}
          </p>
        </div>
      </div>
    </div>
  );
}
