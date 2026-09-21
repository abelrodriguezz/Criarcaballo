import { IconoSenales } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminSenalForm } from "@/components/admin/AdminSenalForm";
import { TarjetaSenalAdmin } from "@/components/admin/TarjetaSenalAdmin";
import { AutoRefresco } from "@/components/ui/AutoRefresco";
import { revisarYCerrarSenalesActivas } from "@/lib/senales/verificarTpSl";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";
import type { Senal } from "@/lib/types";

export default async function PaginaSenales({
  searchParams,
}: {
  searchParams: Promise<{ desde?: string; hasta?: string }>;
}) {
  const { desde, hasta } = await searchParams;
  const [usuario, t, locale] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerDiccionario(),
    obtenerLocale(),
  ]);
  const usuarioEsAdmin = esAdmin(usuario);

  // Revisa las velas de Binance y cierra automáticamente cualquier señal
  // activa que haya tocado TP o SL desde que se publicó — corre en cada
  // carga de esta página (y con el auto-refresh de abajo).
  await revisarYCerrarSenalesActivas();

  const supabase = await crearClienteSupabaseServidor();

  const { data: senales } = await supabase
    .from("senales")
    .select("*")
    .order("created_at", { ascending: false })
    .returns<Senal[]>();

  const recientes = (senales ?? []).filter((s) => !s.resultado);

  let conResultado = (senales ?? []).filter((s) => s.resultado);
  if (desde) {
    const desdeMs = new Date(`${desde}T00:00:00.000Z`).getTime();
    conResultado = conResultado.filter(
      (s) => s.cerrado_en && new Date(s.cerrado_en).getTime() >= desdeMs
    );
  }
  if (hasta) {
    const hastaMs = new Date(`${hasta}T23:59:59.999Z`).getTime();
    conResultado = conResultado.filter(
      (s) => s.cerrado_en && new Date(s.cerrado_en).getTime() <= hastaMs
    );
  }

  return (
    <div className="py-10">
      <AutoRefresco />
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoSenales className="w-6 h-6 text-brand-primary" />
        {t.senales.titulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {t.senales.subtitulo}
      </p>

      {usuarioEsAdmin && <AdminSenalForm />}

      <h2 className="font-display font-semibold text-lg mb-3">
        {t.senales.recientes}
      </h2>
      {recientes.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
          {t.senales.sinRecientes}
        </p>
      ) : (
        <div className="grid md:grid-cols-2 gap-4 mb-8">
          {recientes.map((senal) => (
            <TarjetaSenalAdmin
              key={senal.id}
              senal={senal}
              esAdmin={usuarioEsAdmin}
              t={t}
              locale={locale}
            />
          ))}
        </div>
      )}

      <h2 className="font-display font-semibold text-lg mb-3">
        {t.senales.tocaronTpSl}
      </h2>

      <form
        method="get"
        className="flex flex-wrap items-end gap-3 mb-4 border border-[var(--border)] rounded-2xl p-4"
      >
        <div>
          <label className="block text-[12px] text-foreground-muted mb-1">
            {t.senales.desde}
          </label>
          <input
            type="date"
            name="desde"
            defaultValue={desde ?? ""}
            className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] text-foreground-muted mb-1">
            {t.senales.hasta}
          </label>
          <input
            type="date"
            name="hasta"
            defaultValue={hasta ?? ""}
            className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <button
          type="submit"
          className="bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          {t.senales.filtrar}
        </button>
        {(desde || hasta) && (
          <a
            href="/senales"
            className="text-xs text-foreground-muted hover:underline"
          >
            {t.senales.quitarFiltro}
          </a>
        )}
      </form>

      {conResultado.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          {desde || hasta
            ? t.senales.sinResultadoConFiltro
            : t.senales.sinResultadoSinFiltro}
        </p>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {conResultado.map((senal) => (
            <TarjetaSenalAdmin
              key={senal.id}
              senal={senal}
              esAdmin={usuarioEsAdmin}
              t={t}
              locale={locale}
            />
          ))}
        </div>
      )}
    </div>
  );
}
