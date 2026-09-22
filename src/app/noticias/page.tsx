import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminNoticiaForm } from "@/components/admin/AdminNoticiaForm";
import { TarjetaNoticiaAdmin } from "@/components/admin/TarjetaNoticiaAdmin";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";
import type { Noticia } from "@/lib/types";

export default async function PaginaNoticias() {
  const [usuario, t, locale] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerDiccionario(),
    obtenerLocale(),
  ]);
  const usuarioEsAdmin = esAdmin(usuario);
  const supabase = await crearClienteSupabaseServidor();

  const { data: noticias } = await supabase
    .from("noticias")
    .select("*")
    .order("created_at", { ascending: false })
    .returns<Noticia[]>();

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        {t.noticias.titulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {t.noticias.subtitulo}
      </p>

      {usuarioEsAdmin && <AdminNoticiaForm />}

      {!noticias || noticias.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          {t.noticias.sinNoticias}
        </p>
      ) : (
        <div className="flex flex-col gap-3">
          {noticias.map((noticia) => (
            <TarjetaNoticiaAdmin
              key={noticia.id}
              noticia={noticia}
              esAdmin={usuarioEsAdmin}
              locale={locale}
            />
          ))}
        </div>
      )}
    </div>
  );
}
