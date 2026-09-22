import { IconoInfo } from "@/components/ui/Iconos";
import { obtenerDiccionario } from "@/lib/i18n/servidor";

export default async function PaginaNosotros() {
  const t = await obtenerDiccionario();

  return (
    <div className="py-10 max-w-[640px]">
      <h1 className="font-display font-semibold text-[26px] mb-6">
        {t.nosotros.titulo}
      </h1>

      <p className="text-foreground-muted text-[15px] leading-relaxed mb-4">
        {t.nosotros.parrafo1}
      </p>
      <p className="text-foreground-muted text-[15px] leading-relaxed mb-8">
        {t.nosotros.parrafo2}
      </p>

      <div className="border border-[var(--border)] bg-surface p-5 flex gap-3">
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
