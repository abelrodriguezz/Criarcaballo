import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerConfigPremioReferido } from "@/lib/config-referidos";
import { AdminPremioReferidoForm } from "@/components/admin/AdminPremioReferidoForm";
import { BuscadorReferidos } from "@/components/admin/BuscadorReferidos";
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
      supabase.from("depositos_simulados").select("usuario_id, monto"),
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
        ← Volver a perfil
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Referidos
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {cantidadInvitados}{" "}
        {cantidadInvitados === 1
          ? "persona se registró por invitación"
          : "personas se registraron por invitación"}
        . Cuando un invitado hace su depósito simulado, se le genera
        automáticamente a quien lo invitó una comisión pendiente de pago
        — se paga en USDT vía tarjeta de regalo (gift card), fuera de la
        plataforma. Márcala como pagada aquí cuando ya se la hayas
        enviado.
      </p>

      <h2 className="font-display font-semibold text-lg mb-3">
        Configuración
      </h2>
      <AdminPremioReferidoForm configActual={config} />

      <BuscadorReferidos
        todos={todos}
        comisiones={comisiones}
        bonos={bonos}
        depositos={depositos ?? []}
      />
    </div>
  );
}
