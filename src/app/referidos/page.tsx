import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerConfigPremioReferido } from "@/lib/config-referidos";
import { AdminPremioReferidoForm } from "@/components/admin/AdminPremioReferidoForm";
import { BuscadorReferidos } from "@/components/admin/BuscadorReferidos";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";
import { rellenar } from "@/lib/i18n";
import type { GananciaConcurso } from "@/lib/types";

interface FilaUsuarioCompleta {
  id: string;
  email: string;
  nombre: string | null;
  id_corto: number | null;
  invitado_por: string | null;
  created_at: string;
}

export default async function PaginaReferidos() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const [t, locale] = await Promise.all([obtenerDiccionario(), obtenerLocale()]);
  const ta = t.admin;

  const supabase = await crearClienteSupabaseServidor();

  // Se trae la tabla completa (id/email/id_corto/invitado_por) de una —
  // hace falta para armar el árbol completo (una cadena puede tener
  // varios niveles: A invita a B, B invita a C...), no alcanza con pedir
  // solo "los que tienen invitado_por". El armado del árbol y el filtro
  // de búsqueda viven en BuscadorReferidos (cliente, interactivo).
  const [{ data: todosUsuarios }, { data: premiosReferidos }, config, { data: depositos }] =
    await Promise.all([
      supabase
        .from("usuarios")
        .select("id, email, nombre, id_corto, invitado_por, created_at")
        .order("created_at", { ascending: true })
        .returns<FilaUsuarioCompleta[]>(),
      supabase
        .from("ganancias_concursos")
        .select("*")
        .eq("origen", "referido")
        .returns<GananciaConcurso[]>(),
      obtenerConfigPremioReferido(),
      supabase.from("depositos_simulados").select("usuario_id, monto, pagado"),
    ]);

  const todos = todosUsuarios ?? [];
  const cantidadInvitados = todos.filter((u) => u.invitado_por).length;
  const comisiones = (premiosReferidos ?? []).filter((p) => p.invitado_id);
  const bonos = (premiosReferidos ?? []).filter((p) => !p.invitado_id);

  return (
    <div className="py-10">
      <Link
        href="/perfil"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        {ta.volverAPerfil}
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        {ta.referidosTitulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {rellenar(
          cantidadInvitados === 1 ? ta.referidosInvitadosUno : ta.referidosInvitadosVarios,
          { n: cantidadInvitados }
        )}{" "}
        {ta.referidosIntro}
      </p>

      <h2 className="font-display font-semibold text-lg mb-3">
        {ta.configuracion}
      </h2>
      <AdminPremioReferidoForm configActual={config} ta={ta} />

      <BuscadorReferidos
        todos={todos}
        comisiones={comisiones}
        bonos={bonos}
        depositos={depositos ?? []}
        ta={ta}
        locale={locale}
      />
    </div>
  );
}
