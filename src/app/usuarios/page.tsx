import { redirect } from "next/navigation";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { ListaUsuariosAdmin } from "@/components/admin/ListaUsuariosAdmin";
import type { Usuario, DepositoSimulado } from "@/lib/types";

export default async function PaginaUsuarios() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();
  const [{ data: usuarios }, { data: depositosSimulados }] = await Promise.all([
    supabase
      .from("usuarios")
      .select("*")
      .order("created_at", { ascending: false })
      .returns<Usuario[]>(),
    supabase
      .from("depositos_simulados")
      .select("*")
      .returns<DepositoSimulado[]>(),
  ]);

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Gestión de usuarios
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {usuarios?.length ?? 0}{" "}
        {usuarios?.length === 1 ? "usuario registrado" : "usuarios registrados"}
        . Cambia el rol, desactiva el acceso o bloquea el trading de
        cualquier cuenta.
      </p>

      {!usuarios || usuarios.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          No hay usuarios registrados todavía.
        </p>
      ) : (
        <ListaUsuariosAdmin
          usuarios={usuarios}
          miId={usuarioActual.id}
          depositosSimulados={depositosSimulados ?? []}
        />
      )}
    </div>
  );
}
