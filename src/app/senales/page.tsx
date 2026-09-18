import { IconoSenales } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminSenalForm } from "@/components/admin/AdminSenalForm";
import { TarjetaSenalAdmin } from "@/components/admin/TarjetaSenalAdmin";
import type { Senal } from "@/lib/types";

export default async function PaginaSenales() {
  const usuario = await obtenerUsuarioActual();
  const usuarioEsAdmin = esAdmin(usuario);
  const supabase = await crearClienteSupabaseServidor();

  const { data: senales } = await supabase
    .from("senales")
    .select("*")
    .order("created_at", { ascending: false })
    .returns<Senal[]>();

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoSenales className="w-6 h-6 text-brand-primary" />
        Señales recientes
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Publicadas desde el panel admin, con razón incluida.
      </p>

      {usuarioEsAdmin && <AdminSenalForm />}

      {!senales || senales.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía no hay señales publicadas.
        </p>
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {senales.map((senal) => (
            <TarjetaSenalAdmin key={senal.id} senal={senal} esAdmin={usuarioEsAdmin} />
          ))}
        </div>
      )}
    </div>
  );
}
