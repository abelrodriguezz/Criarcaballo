"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ArbolReferidos, type NodoArbolReferido } from "@/components/admin/ArbolReferidos";
import { BotonExportarArbolReferidos } from "@/components/admin/BotonExportarArbolReferidos";
import { BotonPagoGanancia } from "@/components/admin/BotonPagoGanancia";
import { formatearDinero } from "@/lib/format";
import type { GananciaConcurso } from "@/lib/types";

interface UsuarioReferido extends NodoArbolReferido {
  created_at: string;
  invitado_por: string | null;
}

interface DepositoPlano {
  usuario_id: string;
  monto: number;
}

export function BuscadorReferidos({
  todos,
  comisiones,
  bonos,
  depositos,
}: {
  todos: UsuarioReferido[];
  comisiones: GananciaConcurso[];
  bonos: GananciaConcurso[];
  depositos: DepositoPlano[];
}) {
  const [busqueda, setBusqueda] = useState("");
  // Al hacer clic en alguien del árbol, se vuelve la "raíz" de la vista
  // (se ve su propia red hacia abajo) en vez de navegar a su perfil.
  const [raizManual, setRaizManual] = useState<string | null>(null);

  // Los Map no viajan como prop de servidor a cliente — se arman aquí,
  // una vez, a partir de los arrays planos que sí llegan serializados.
  const { emailPorUsuario, nombrePorUsuario, hijosPorPadre, raices, comisionPorInvitado, depositoPorUsuario } =
    useMemo(() => {
      const filas = todos.filter((u) => u.invitado_por);
      const emailPorUsuario = new Map(todos.map((u) => [u.id, u.email]));
      const nombrePorUsuario = new Map(todos.map((u) => [u.id, u.nombre]));
      const hijosPorPadre = new Map<string, UsuarioReferido[]>();
      for (const u of filas) {
        const padre = u.invitado_por as string;
        if (!hijosPorPadre.has(padre)) hijosPorPadre.set(padre, []);
        hijosPorPadre.get(padre)!.push(u);
      }
      const raices = todos.filter((u) => !u.invitado_por && hijosPorPadre.has(u.id));
      const comisionPorInvitado = new Map(
        comisiones.map((c) => [c.invitado_id as string, { id: c.id, monto: c.monto, pagado: c.pagado }])
      );
      const depositoPorUsuario = new Map(depositos.map((d) => [d.usuario_id, Number(d.monto)]));
      return { emailPorUsuario, nombrePorUsuario, hijosPorPadre, raices, comisionPorInvitado, depositoPorUsuario };
    }, [todos, comisiones, depositos]);

  const filas = useMemo(() => todos.filter((u) => u.invitado_por), [todos]);

  // Qué se muestra como "raíz" del árbol:
  // 1) si se seleccionó a alguien haciendo clic, esa persona sola (con su
  //    propia red completa hacia abajo, ignorando la búsqueda);
  // 2) si hay una búsqueda activa, cada coincidencia se vuelve su propia
  //    raíz — así "buscar a Carlos" muestra a Carlos como principal, no
  //    enterrado bajo quien lo invitó a él;
  // 3) si no hay nada de eso, las raíces reales (quienes no fueron
  //    invitados por nadie).
  // hijosPorPadre se pasa siempre completo — la raíz elegida muestra TODA
  // su red hacia abajo, no una versión recortada por el texto buscado.
  const raicesEfectivas = useMemo(() => {
    if (raizManual) {
      const seleccionado = todos.find((u) => u.id === raizManual);
      if (seleccionado) return [seleccionado];
    }

    const termino = busqueda.trim().toLowerCase();
    if (!termino) return raices;

    const coincide = (u: UsuarioReferido) =>
      u.email.toLowerCase().includes(termino) ||
      (!!u.nombre && u.nombre.toLowerCase().includes(termino)) ||
      (u.id_corto != null && String(u.id_corto).includes(termino));

    return todos.filter(coincide);
  }, [raizManual, busqueda, todos, raices]);

  function seleccionarComoPrincipal(id: string) {
    setRaizManual(id);
    setBusqueda("");
  }

  const filasFiltradas = useMemo(() => {
    const termino = busqueda.trim().toLowerCase();
    if (!termino) return filas;
    return filas.filter((f) => {
      const emailInvitador = emailPorUsuario.get(f.invitado_por as string) ?? "";
      const nombreInvitador = nombrePorUsuario.get(f.invitado_por as string) ?? "";
      return (
        f.email.toLowerCase().includes(termino) ||
        (!!f.nombre && f.nombre.toLowerCase().includes(termino)) ||
        (f.id_corto != null && String(f.id_corto).includes(termino)) ||
        emailInvitador.toLowerCase().includes(termino) ||
        nombreInvitador.toLowerCase().includes(termino)
      );
    });
  }, [busqueda, filas, emailPorUsuario, nombrePorUsuario]);

  const bonosFiltrados = useMemo(() => {
    const termino = busqueda.trim().toLowerCase();
    if (!termino) return bonos;
    return bonos.filter((b) => {
      const email = emailPorUsuario.get(b.usuario_id) ?? "";
      const nombre = nombrePorUsuario.get(b.usuario_id) ?? "";
      return (
        email.toLowerCase().includes(termino) ||
        nombre.toLowerCase().includes(termino)
      );
    });
  }, [busqueda, bonos, emailPorUsuario, nombrePorUsuario]);

  return (
    <div>
      <input
        value={busqueda}
        onChange={(e) => {
          setBusqueda(e.target.value);
          setRaizManual(null);
        }}
        placeholder="Buscar por nombre, correo o ID de usuario..."
        aria-label="Buscar referido"
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <div className="flex flex-wrap items-center justify-between gap-3 mb-3">
        <h2 className="font-display font-semibold text-lg">
          Árbol de referidos
        </h2>
        <BotonExportarArbolReferidos
          raices={raicesEfectivas}
          hijosPorPadre={hijosPorPadre}
          depositoPorUsuario={depositoPorUsuario}
          comisionPorInvitado={comisionPorInvitado}
          emailPorUsuario={emailPorUsuario}
          nombrePorUsuario={nombrePorUsuario}
        />
      </div>
      <p className="text-foreground-muted text-[12px] mb-3">
        Quién invitó a quién, en cadena — no solo el nivel directo. Toca
        el nombre de cualquier persona para verla como principal y ver
        solo su propia red hacia abajo.
      </p>
      {raizManual && (
        <div className="flex flex-wrap items-center gap-2 mb-3 text-[13px]">
          <span className="text-foreground-muted">Mostrando la red de</span>
          <span className="font-semibold">
            {nombrePorUsuario.get(raizManual) ?? emailPorUsuario.get(raizManual) ?? "esta persona"}
          </span>
          <button
            type="button"
            onClick={() => setRaizManual(null)}
            className="text-brand-primary font-semibold hover:underline"
          >
            ← Volver al árbol completo
          </button>
        </div>
      )}
      {raicesEfectivas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
          {busqueda
            ? `Ningún referido coincide con "${busqueda}".`
            : "Todavía no hay ninguna cadena de referidos."}
        </p>
      ) : (
        <ArbolReferidos
          raices={raicesEfectivas}
          hijosPorPadre={hijosPorPadre}
          depositoPorUsuario={depositoPorUsuario}
          comisionPorInvitado={comisionPorInvitado}
          onSeleccionar={seleccionarComoPrincipal}
        />
      )}

      <h2 className="font-display font-semibold text-lg mb-1">
        Comisiones por referido
      </h2>
      <p className="text-foreground-muted text-[12px] mb-3">
        Una fila por cada persona invitada. &quot;Sin comisión todavía&quot;
        significa que esa persona no ha hecho su depósito simulado — en
        cuanto lo haga, aparece aquí el monto pendiente y el botón para
        marcarlo pagado.
      </p>
      {filasFiltradas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
          {busqueda
            ? `Ningún referido coincide con "${busqueda}".`
            : "Todavía nadie se ha registrado con un código de invitación."}
        </p>
      ) : (
        <div className="flex flex-col gap-2.5 mb-8">
          {filasFiltradas.map((f) => {
            const comision = comisionPorInvitado.get(f.id);
            const deposito = depositoPorUsuario.get(f.id);
            return (
              <div
                key={f.id}
                className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3"
              >
                <div className="min-w-0">
                  <div className="text-sm font-medium break-all">
                    {f.nombre ? `${f.nombre} · ${f.email}` : f.email}
                  </div>
                  <div className="text-[12px] text-foreground-muted break-all">
                    Invitado por{" "}
                    <Link
                      href={`/usuarios/${f.invitado_por}`}
                      className="font-medium hover:text-brand-primary"
                    >
                      {emailPorUsuario.get(f.invitado_por as string) ?? "—"}
                    </Link>{" "}
                    ·{" "}
                    {new Date(f.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    {deposito != null
                      ? `Depósito simulado: $${formatearDinero(deposito)}`
                      : "Todavía no hizo su depósito simulado"}
                  </div>
                </div>

                <div className="shrink-0">
                  {!comision ? (
                    <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-foreground-muted/15 text-foreground-muted">
                      Sin comisión todavía
                    </span>
                  ) : (
                    <div className="flex items-center gap-3">
                      <span
                        className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                          comision.pagado
                            ? "bg-gain/15 text-gain"
                            : "bg-brand-secondary/15 text-brand-secondary"
                        }`}
                      >
                        {comision.pagado ? "Pagado" : "Pendiente"} · $
                        {formatearDinero(comision.monto)}
                      </span>
                      <BotonPagoGanancia
                        gananciaId={comision.id}
                        pagado={comision.pagado}
                      />
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <h2 className="font-display font-semibold text-lg mb-1">
        Bonos por meta de referidos
      </h2>
      <p className="text-foreground-muted text-[12px] mb-3">
        Premio extra (aparte de la comisión normal) que se otorga solo
        cuando alguien acumula referidos que ya depositaron en múltiplos
        de la cantidad configurada arriba — por ejemplo, al llegar a 10,
        20, 30... Vacío hasta que alguien alcance la primera meta.
      </p>
      {bonosFiltrados.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          {busqueda
            ? `Ningún bono coincide con "${busqueda}".`
            : "Todavía no se alcanzó ninguna meta de referidos calificados."}
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {bonosFiltrados.map((b) => (
            <div
              key={b.id}
              className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3"
            >
              <div className="min-w-0">
                <div className="text-sm font-medium break-all">
                  {emailPorUsuario.get(b.usuario_id) ?? "Usuario"}
                </div>
                <div className="text-[12px] text-foreground-muted">
                  {b.concepto} ·{" "}
                  {new Date(b.created_at).toLocaleDateString("es-DO", {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  })}
                </div>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                <span
                  className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                    b.pagado
                      ? "bg-gain/15 text-gain"
                      : "bg-brand-secondary/15 text-brand-secondary"
                  }`}
                >
                  {b.pagado ? "Pagado" : "Pendiente"} · $
                  {formatearDinero(b.monto)}
                </span>
                <BotonPagoGanancia gananciaId={b.id} pagado={b.pagado} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
