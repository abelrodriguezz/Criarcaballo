import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { CerrarSesionBoton } from "@/components/auth/CerrarSesionBoton";
import { BotonFavorito } from "@/components/mercado/BotonFavorito";
import { WalletForm } from "@/components/perfil/WalletForm";
import { obtenerVariosPreciosCripto } from "@/lib/market/binance";
import type { GananciaConcurso } from "@/lib/types";

export default async function PaginaPerfil() {
  const usuario = await obtenerUsuarioActual();

  if (!usuario) {
    redirect("/login");
  }
  if (!usuario.activo) {
    redirect("/cuenta-desactivada");
  }

  const supabase = await crearClienteSupabaseServidor();
  const [
    { data: saldo },
    { data: favoritosGuardados },
    { count: noLeidos },
    { data: perfilExtra },
    { data: ganancias },
  ] = await Promise.all([
    supabase
      .from("saldo_virtual")
      .select("saldo_usd")
      .eq("usuario_id", usuario.id)
      .single(),
    supabase
      .from("favoritos")
      .select("activo")
      .eq("usuario_id", usuario.id),
    esAdmin(usuario)
      ? supabase
          .from("mensajes_soporte")
          .select("id", { count: "exact", head: true })
          .eq("leido_admin", false)
      : supabase
          .from("mensajes_soporte")
          .select("id", { count: "exact", head: true })
          .eq("usuario_id", usuario.id)
          .eq("leido_usuario", false),
    supabase
      .from("usuarios")
      .select("wallet_usdt_erc20, id_corto")
      .eq("id", usuario.id)
      .single(),
    supabase
      .from("ganancias_concursos")
      .select("*")
      .eq("usuario_id", usuario.id)
      .order("created_at", { ascending: false })
      .returns<GananciaConcurso[]>(),
  ]);

  const totalGanancias = (ganancias ?? []).reduce(
    (suma, g) => suma + g.monto,
    0
  );
  const pendienteGanancias = (ganancias ?? [])
    .filter((g) => !g.pagado)
    .reduce((suma, g) => suma + g.monto, 0);

  const simbolosFavoritos = (favoritosGuardados ?? []).map((f) => f.activo);
  const preciosFavoritos = await obtenerVariosPreciosCripto(simbolosFavoritos);

  return (
    <div className="py-10 max-w-[520px]">
      <h1 className="font-display font-semibold text-[26px] mb-7">Perfil</h1>

      <div className="border border-[var(--border)] rounded-2xl p-5 mb-4">
        <div className="flex justify-between items-center mb-4 gap-3">
          <div className="min-w-0">
            {perfilExtra?.id_corto && (
              <div className="text-[12px] font-mono text-foreground-muted mb-0.5">
                ID: {perfilExtra.id_corto}
              </div>
            )}
            <div className="text-[13px] text-foreground-muted">Correo</div>
            <div className="font-medium text-sm break-all">
              {usuario.email}
            </div>
          </div>
          {esAdmin(usuario) && (
            <span className="shrink-0 bg-brand-primary/15 text-brand-primary text-xs font-bold px-3 py-1 rounded-full">
              Admin
            </span>
          )}
        </div>

        <div className="border-t border-[var(--border)] pt-4">
          <div className="text-[13px] text-foreground-muted mb-1">
            Saldo virtual (paper trading)
          </div>
          <div className="font-display font-bold text-2xl tabular">
            ${saldo?.saldo_usd?.toLocaleString("en-US", { minimumFractionDigits: 2 }) ?? "10,000.00"}
          </div>
        </div>
      </div>

      <WalletForm
        usuarioId={usuario.id}
        walletActual={perfilExtra?.wallet_usdt_erc20 ?? null}
      />

      <div className="border border-[var(--border)] rounded-2xl p-5 mb-4">
        <div className="flex justify-between items-center mb-3">
          <div className="font-medium text-sm">Ganancias</div>
          {totalGanancias > 0 && (
            <span className="font-display font-bold text-gain tabular">
              +${totalGanancias.toLocaleString("en-US", { minimumFractionDigits: 2 })}
            </span>
          )}
        </div>
        {pendienteGanancias > 0 && (
          <div className="bg-brand-secondary/10 rounded-lg px-3 py-2 mb-3 flex justify-between items-center">
            <span className="text-[13px] text-foreground-muted">
              Pendiente por recibir
            </span>
            <span className="font-display font-bold text-sm text-brand-secondary tabular">
              ${pendienteGanancias.toLocaleString("en-US", { minimumFractionDigits: 2 })}
            </span>
          </div>
        )}
        {!ganancias || ganancias.length === 0 ? (
          <p className="text-[13px] text-foreground-muted">
            Todavía no has ganado ningún concurso. Cuando ganes uno, el
            premio se pagará a tu wallet y quedará reflejado aquí.
          </p>
        ) : (
          <div className="flex flex-col gap-2">
            {ganancias.map((g) => (
              <div
                key={g.id}
                className="flex items-center justify-between py-1"
              >
                <div>
                  <div className="text-sm font-medium">
                    {g.concepto || "Sin concepto"}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    {new Date(g.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}{" "}
                    · {g.pagado ? "Pagado" : "Pendiente"}
                  </div>
                </div>
                <span className="font-display font-bold text-sm text-gain tabular">
                  +${g.monto.toLocaleString("en-US", { minimumFractionDigits: 2 })}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="border border-[var(--border)] rounded-2xl p-5 mb-4">
        <div className="font-medium text-sm mb-3">Favoritos</div>
        {simbolosFavoritos.length === 0 ? (
          <p className="text-[13px] text-foreground-muted">
            Aún no marcaste ningún activo como favorito. Hazlo desde{" "}
            <span className="font-medium">Mercado</span> tocando la estrella
            junto al precio.
          </p>
        ) : (
          <div className="flex flex-col gap-2">
            {preciosFavoritos.map((activo) => (
              <div
                key={activo.simbolo}
                className="flex items-center justify-between py-1.5"
              >
                <div className="flex items-center gap-2">
                  <BotonFavorito
                    activo={activo.simbolo}
                    esFavoritoInicial={true}
                  />
                  <span className="text-sm font-medium">
                    {activo.simbolo}
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-sm tabular">
                    $
                    {activo.precio.toLocaleString("en-US", {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 6,
                    })}
                  </span>
                  <span
                    className={`text-xs font-semibold ${
                      activo.cambioPorc24h >= 0 ? "text-gain" : "text-loss"
                    }`}
                  >
                    {activo.cambioPorc24h >= 0 ? "+" : ""}
                    {activo.cambioPorc24h.toFixed(2)}%
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {esAdmin(usuario) && (
        <Link
          href="/usuarios"
          className="border border-[var(--border)] rounded-2xl p-5 mb-4 flex justify-between items-center hover:bg-surface-hover transition-colors"
        >
          <div>
            <div className="font-medium text-sm">Gestión de usuarios</div>
            <div className="text-[13px] text-foreground-muted">
              Cambiar roles y activar/desactivar cuentas
            </div>
          </div>
        </Link>
      )}

      <Link
        href="/soporte"
        className="border border-[var(--border)] rounded-2xl p-5 mb-4 flex justify-between items-center hover:bg-surface-hover transition-colors"
      >
        <div>
          <div className="font-medium text-sm">
            {esAdmin(usuario) ? "Bandeja de soporte" : "Contactar soporte"}
          </div>
          <div className="text-[13px] text-foreground-muted">
            {esAdmin(usuario)
              ? "Conversaciones de usuarios, en orden de llegada"
              : "¿Alguna duda? Escríbenos"}
          </div>
        </div>
        {!!noLeidos && (
          <span className="shrink-0 bg-brand-secondary text-white text-xs font-bold px-2.5 py-1 rounded-full ml-3">
            {noLeidos}
          </span>
        )}
      </Link>

      <div className="border border-[var(--border)] rounded-2xl p-5 flex justify-between items-center">
        <div>
          <div className="font-medium text-sm">Configuración de cuenta</div>
          <div className="text-[13px] text-foreground-muted">
            Notificaciones próximamente
          </div>
        </div>
        <CerrarSesionBoton />
      </div>
    </div>
  );
}
