import { LoginForm } from "@/components/auth/LoginForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaLogin({
  searchParams,
}: {
  searchParams: Promise<{ motivo?: string }>;
}) {
  const [t, locale, { motivo }] = await Promise.all([
    obtenerDiccionario(),
    obtenerLocale(),
    searchParams,
  ]);
  return (
    <div className="py-16">
      <LoginForm t={t} locale={locale} cerradaPorInactividad={motivo === "inactividad"} />
    </div>
  );
}
