import { Suspense } from "react";
import { RegistroForm } from "@/components/auth/RegistroForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaRegistro() {
  const [t, locale] = await Promise.all([obtenerDiccionario(), obtenerLocale()]);
  return (
    <div className="py-16">
      <Suspense fallback={null}>
        <RegistroForm t={t} locale={locale} />
      </Suspense>
    </div>
  );
}
