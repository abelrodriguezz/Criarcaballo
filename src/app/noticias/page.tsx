import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminNoticiaForm } from "@/components/admin/AdminNoticiaForm";
import { TarjetaNoticiaAdmin } from "@/components/admin/TarjetaNoticiaAdmin";
import type { Noticia } from "@/lib/types";

export default async function PaginaNoticias() {
  const usuario = await obtenerUsuarioActual();
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
        Noticias
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Actualizaciones filtradas del mercado.
      </p>

      {usuarioEsAdmin && <AdminNoticiaForm />}

      {!noticias || noticias.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía no hay noticias publicadas.
        </p>
      ) : (
        <div className="flex flex-col gap-3">
          {noticias.map((noticia) => (
            <TarjetaNoticiaAdmin
              key={noticia.id}
              noticia={noticia}
              esAdmin={usuarioEsAdmin}
            />
          ))}
        </div>
      )}
    </div>
  );
}
