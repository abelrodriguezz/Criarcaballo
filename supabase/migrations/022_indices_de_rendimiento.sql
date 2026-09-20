-- ============================================================================
-- 022 — Índices para las consultas que van a crecer con el uso real
-- ============================================================================
-- Auditoría de rendimiento previa al despliegue. Hasta aquí las únicas tablas
-- con índices propios eran mensajes_soporte y ganancias_concursos; todo lo
-- demás dependía de la clave primaria, así que cada listado hacía un recorrido
-- secuencial de la tabla entera. Con 2 usuarios de prueba eso no se nota; con
-- miles de operaciones y señales sí, y el plan gratuito de Supabase es
-- justamente donde peor sienta.
--
-- Solo se AGREGAN índices: no se toca ninguna política, función ni columna.
-- Cada uno responde a una consulta concreta que ya existe en el código.
--
-- Nota sobre CONCURRENTLY: no se usa a propósito. Estas tablas son pequeñas
-- hoy, y CREATE INDEX CONCURRENTLY no puede correr dentro de una transacción,
-- lo que complicaría aplicar la migración de un tirón en una instalación nueva
-- (que es como la va a correr quien reciba el proyecto).
-- ============================================================================

-- ── operaciones_simuladas ───────────────────────────────────────────────────

-- /trade-del-dia: historial del usuario
--   .eq(usuario_id).eq(estado,'cerrada').order(cerrado_en desc).limit(5)
-- y /usuarios/[id]: .eq(usuario_id).order(created_at desc).limit(20)
create index if not exists operaciones_usuario_created_at_idx
  on public.operaciones_simuladas (usuario_id, created_at desc);

create index if not exists operaciones_usuario_cerrado_en_idx
  on public.operaciones_simuladas (usuario_id, cerrado_en desc)
  where estado = 'cerrada';

-- reporte_operaciones_por_dia(p_inicio, p_fin): rango de fechas sobre TODA la
-- tabla, agrupando por usuario. Es la consulta que decide a quién se le paga
-- el premio, y la que más va a crecer (una fila por operación de cada día).
create index if not exists operaciones_created_at_idx
  on public.operaciones_simuladas (created_at);

-- Cierre masivo del admin y la tarjeta de "símbolos abiertos":
--   .select(...).eq('estado','abierta')
-- Índice parcial: solo indexa las abiertas, que siempre serán un puñado
-- frente al histórico completo de cerradas.
create index if not exists operaciones_abiertas_idx
  on public.operaciones_simuladas (activo)
  where estado = 'abierta';

-- ── senales ─────────────────────────────────────────────────────────────────

-- /senales: .order(created_at desc) sobre la tabla completa (página pública).
create index if not exists senales_created_at_idx
  on public.senales (created_at desc);

-- revisarYCerrarSenalesActivas(): .eq('estado','activa').is('resultado',null)
-- Corre en CADA carga de /senales, así que conviene que sea instantánea.
create index if not exists senales_activas_idx
  on public.senales (created_at)
  where estado = 'activa' and resultado is null;

-- ── noticias ────────────────────────────────────────────────────────────────

-- Portada: .order(destacada desc).order(created_at desc).limit(6)
-- y /noticias: .order(created_at desc)
create index if not exists noticias_destacada_created_at_idx
  on public.noticias (destacada desc, created_at desc);

-- ── ganancias_concursos ─────────────────────────────────────────────────────

-- Ya existe (usuario_id, created_at), pero /perfil y /usuarios/[id] ordenan
-- DESC; con el índice ascendente Postgres igual lo puede recorrer al revés,
-- así que no se duplica. Lo que sí falta es el filtro de pendientes de pago.
create index if not exists ganancias_pendientes_idx
  on public.ganancias_concursos (usuario_id)
  where not pagado;

-- ── usuarios ────────────────────────────────────────────────────────────────

-- /usuarios: .order(created_at desc) con la lista completa de cuentas.
create index if not exists usuarios_created_at_idx
  on public.usuarios (created_at desc);

-- contar_invitados() y el contador de "personas invitadas" de /usuarios/[id]:
--   where invitado_por = <id>
create index if not exists usuarios_invitado_por_idx
  on public.usuarios (invitado_por)
  where invitado_por is not null;

-- /usuarios/reportes: .select(id, email, id_corto).order('email')
create index if not exists usuarios_email_idx
  on public.usuarios (email);

-- ── favoritos ───────────────────────────────────────────────────────────────
-- No necesita nada: la clave primaria es (usuario_id, activo), así que las
-- consultas por usuario_id ya usan el prefijo de ese índice.

-- ── mensajes_soporte ────────────────────────────────────────────────────────
-- Ya tiene (usuario_id, created_at) y (remitente_id, created_at desc), que
-- cubren la conversación, el límite de frecuencia y listar_conversaciones_soporte.
-- Falta el contador de no leídos del badge de /perfil para el admin:
--   .select(id, head, count).eq('leido_admin', false)
create index if not exists mensajes_no_leidos_admin_idx
  on public.mensajes_soporte (created_at)
  where not leido_admin;

analyze public.operaciones_simuladas;
analyze public.senales;
analyze public.noticias;
analyze public.usuarios;
analyze public.ganancias_concursos;
analyze public.mensajes_soporte;
