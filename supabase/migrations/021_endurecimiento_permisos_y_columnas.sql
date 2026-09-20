-- ============================================================
-- MIGRACIÓN 021: Endurecimiento de permisos de RPC, columnas
-- inmutables y sanitización de URLs
-- Pegar en Supabase → SQL Editor → Run (después de 001-020)
--
-- Segunda auditoría de seguridad independiente sobre las migraciones
-- 001-020. Corrige, de más grave a menos:
--
-- 1) EL VALIDADOR DEL SECRETO DE SERVIDOR ERA INVOCABLE DESDE EL NAVEGADOR.
--    La migración 019 creó public.secreto_servidor_ok(text) y le hizo
--    "revoke execute ... from public", pero eso NO alcanza en Supabase:
--    el proyecto tiene privilegios por defecto que otorgan EXECUTE
--    explícitamente a los roles `anon` y `authenticated` sobre toda
--    función nueva del esquema public. Revocarle a PUBLIC no toca esos
--    grants nominales, así que la función quedó expuesta en la API REST.
--    Verificado contra la base real: con la anon key (que viaja en el
--    bundle del navegador) y SIN NINGUNA SESIÓN se podía llamar
--      supabase.rpc('secreto_servidor_ok', {p_secreto: '...'})
--    y recibir true/false. Eso convierte al secreto compartido —la única
--    barrera que impide abrir operaciones con precio inventado (bug #2 de
--    la migración 019) y falsificar el resultado de una señal (bug #3)—
--    en un oráculo verificable: cualquiera puede confirmar un candidato
--    sin límite de intentos, y confirmar de inmediato el que aparece
--    escrito en el propio archivo de la migración 019 (ver punto 6).
--    Se revoca EXECUTE de anon/authenticated/PUBLIC: la función solo la
--    necesitan las otras funciones SECURITY DEFINER, que corren como
--    `postgres` y no pasan por estos grants.
--    Por el mismo motivo se le quita el EXECUTE a `anon` a las funciones
--    que exigen sesión o rol admin, y a PUBLIC a las funciones de trigger
--    (handle_new_user, handle_new_user_saldo,
--    proteger_columnas_sensibles_usuarios), que nunca deben poder
--    invocarse como RPC.
--
-- 2) UN USUARIO PODÍA REESCRIBIR MENSAJES YA ENVIADOS.
--    La política UPDATE de mensajes_soporte solo comprobaba de quién es la
--    conversación, no QUÉ columna se estaba cambiando. La app solo marca
--    mensajes como leídos, pero con la anon key un usuario podía hacer
--      supabase.from('mensajes_soporte').update({contenido: '...'})
--    sobre CUALQUIER mensaje de su conversación — incluidas las respuestas
--    del admin. Verificado contra la base real. Riesgo: repudio y
--    fabricación de evidencia ("el soporte me autorizó X"), justo en el
--    canal que respalda pagos de premios en USDT. Se agrega un trigger que
--    congela todas las columnas salvo los dos flags de leído.
--
-- 3) UN USUARIO PODÍA CAMBIAR SU PROPIO EMAIL, CÓDIGO DE INVITACIÓN,
--    ID CORTO E INVITADO_POR.
--    El trigger de la migración 010/012 solo protege role, activo y
--    trading_habilitado; la política UPDATE de `usuarios` no tiene
--    "with check" por columna, así que el resto de la fila quedaba
--    escribible por su dueño. Verificado contra la base real: un usuario
--    normal cambió el email de su fila a "soporte@trade4u.test". Ese email
--    es lo que el admin ve en /usuarios, /usuarios/[id], la bandeja de
--    soporte y el CSV de reportes, o sea que servía para suplantar al
--    equipo frente al propio admin. id_corto y codigo_invitacion permiten
--    lo mismo con el identificador que el usuario "dice en voz alta", e
--    invitado_por falsea el conteo de referidos. Se extiende el trigger
--    para congelar esas columnas salvo para un admin. El único campo que
--    un usuario normal puede seguir editando de su fila es
--    wallet_usdt_erc20, que es el propósito del formulario de Perfil.
--
-- 4) SECURITY DEFINER SIN search_path FIJO.
--    Ninguna de las funciones fijaba search_path (lint
--    `function_search_path_mutable` de Supabase). Hoy no es explotable en
--    este proyecto —ni anon ni authenticated tienen CREATE sobre el
--    esquema public, verificado— pero es una bomba de tiempo: basta con
--    que alguien otorgue ese permiso más adelante para que se pueda
--    secuestrar la resolución de nombres dentro de funciones que corren
--    como `postgres`. Se fija en todas.
--
-- 5) noticias.url_fuente ACEPTABA CUALQUIER TEXTO.
--    Ese valor se renderiza como href en la portada (ticker) y en
--    /noticias. Un valor "javascript:..." es XSS almacenado para todos los
--    visitantes, incluido el admin. Se restringe a http/https en la base
--    (el front además lo sanea al renderizar, defensa en profundidad).
--
-- 6) EL SECRETO DE SERVIDOR ESTABA ESCRITO EN TEXTO PLANO EN LA MIGRACIÓN
--    019, que se versiona y se entrega con el proyecto. Se quitó de ese
--    archivo y el valor se rota fuera de git (ver nota al final).
--
-- 7) TRUNCATE/TRIGGER/REFERENCES otorgados a anon/authenticated.
--    Son parte del "grant all" por defecto de Supabase. PostgREST nunca
--    los usa, pero TRUNCATE en particular NO respeta RLS, así que
--    cualquier vía futura de SQL con esos roles podría vaciar tablas de
--    dinero saltándose todas las políticas. Se revocan.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Permisos de ejecución de funciones
-- ------------------------------------------------------------

-- El validador del secreto: nadie externo debe poder invocarlo. Las
-- funciones que lo usan son SECURITY DEFINER y corren como su dueño, así
-- que siguen pudiendo llamarlo aunque el rol de la sesión no pueda.
revoke all on function public.secreto_servidor_ok(text) from public, anon, authenticated;

-- Funciones de trigger: no son RPC, jamás deben exponerse en la API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_new_user_saldo() from public, anon, authenticated;
revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- Funciones que exigen sesión o rol admin: `anon` no tiene nada que hacer
-- ahí (ya fallaban dentro, pero no hace falta ni dejarlas invocables).
revoke all on function public.abrir_operacion(text, text, numeric, numeric, text) from anon;
revoke all on function public.cerrar_operacion(uuid, numeric) from anon;
revoke all on function public.admin_cerrar_operacion(uuid, numeric) from anon;
revoke all on function public.admin_agregar_saldo(uuid, numeric) from anon;
revoke all on function public.contar_invitados() from public, anon;
revoke all on function public.listar_conversaciones_soporte() from public, anon;
revoke all on function public.reporte_operaciones_por_dia(timestamptz, timestamptz)
  from public, anon;
-- OJO: es_admin() NO se le revoca a `anon`. No es una fuga (para una
-- sesión sin usuario siempre devuelve false), y sobre todo aparece dentro
-- de las políticas RLS de mensajes_soporte, ganancias_concursos, usuarios,
-- senales, noticias, etc. Esas políticas se evalúan con el rol de la
-- sesión, así que sin EXECUTE un visitante anónimo recibiría
-- "permission denied for function es_admin" en vez de simplemente no ver
-- filas — y eso rompería la portada pública.
revoke all on function public.es_admin() from public;

-- Se reafirma explícitamente lo que SÍ debe poder llamar cada rol, para
-- que la migración sea idempotente y el estado final quede declarado.
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;
grant execute on function public.contar_invitados() to authenticated;
grant execute on function public.listar_conversaciones_soporte() to authenticated;
grant execute on function public.reporte_operaciones_por_dia(timestamptz, timestamptz) to authenticated;
grant execute on function public.es_admin() to anon, authenticated;
-- estadisticas_publicas solo devuelve totales agregados: sigue siendo
-- pública a propósito (la portada la usa sin sesión).
grant execute on function public.estadisticas_publicas() to anon, authenticated;
-- cerrar_senal_automatica sigue disponible para anon a propósito (corre
-- en un Server Component que puede servir a un visitante sin sesión);
-- lo que autoriza de verdad es el secreto, no el rol.
grant execute on function public.cerrar_senal_automatica(uuid, text, text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2) search_path fijo en todas las funciones SECURITY DEFINER
-- ------------------------------------------------------------
-- pg_temp va al final a propósito: por defecto Postgres busca el esquema
-- temporal ANTES que public al resolver nombres de tabla, así que una
-- sesión que pudiera crear tablas temporales podría hacerle sombra a una
-- tabla real dentro de una función que corre como `postgres`.

alter function public.es_admin() set search_path = pg_catalog, public, pg_temp;
alter function public.contar_invitados() set search_path = pg_catalog, public, pg_temp;
alter function public.handle_new_user() set search_path = pg_catalog, public, pg_temp;
alter function public.handle_new_user_saldo() set search_path = pg_catalog, public, pg_temp;
alter function public.proteger_columnas_sensibles_usuarios()
  set search_path = pg_catalog, public, pg_temp;
alter function public.secreto_servidor_ok(text) set search_path = pg_catalog, public, pg_temp;
alter function public.abrir_operacion(text, text, numeric, numeric, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.cerrar_operacion(uuid, numeric) set search_path = pg_catalog, public, pg_temp;
alter function public.admin_cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;
alter function public.admin_agregar_saldo(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;
alter function public.cerrar_senal_automatica(uuid, text, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.listar_conversaciones_soporte()
  set search_path = pg_catalog, public, pg_temp;
alter function public.reporte_operaciones_por_dia(timestamptz, timestamptz)
  set search_path = pg_catalog, public, pg_temp;
alter function public.estadisticas_publicas() set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 3) mensajes_soporte: un mensaje enviado es inmutable
-- ------------------------------------------------------------
-- Lo único que la app actualiza de un mensaje son los dos flags de
-- "leído" (ver src/lib/actions/chat.ts). Todo lo demás —contenido, quién
-- lo escribió, de quién es la conversación, cuándo— queda congelado para
-- todos, admin incluido: un historial de soporte que se puede editar a
-- posteriori no sirve como respaldo de nada.

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at then
    raise exception 'Un mensaje de soporte enviado no se puede modificar; solo marcarse como leído.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_editar_mensaje_soporte on public.mensajes_soporte;
create trigger antes_de_editar_mensaje_soporte
  before update on public.mensajes_soporte
  for each row execute procedure public.proteger_mensajes_soporte();

revoke all on function public.proteger_mensajes_soporte() from public, anon, authenticated;

-- La política de UPDATE pasa a declarar su "with check" explícitamente.
-- Sin él, Postgres reutiliza el "using" como check (que es lo que hoy
-- impide mover un mensaje a otra conversación), pero dejarlo implícito
-- hace que el día que alguien afloje el "using" se afloje también,
-- silenciosamente, lo que se puede escribir.
drop policy if exists "marcar como leido en conversacion propia o si es admin"
  on public.mensajes_soporte;

create policy "marcar como leido en conversacion propia o si es admin"
  on public.mensajes_soporte for update
  using (usuario_id = auth.uid() or public.es_admin())
  with check (usuario_id = auth.uid() or public.es_admin());

-- ------------------------------------------------------------
-- 4) usuarios: columnas de identidad congeladas para el no-admin
-- ------------------------------------------------------------
-- Reemplaza la versión de la migración 012 agregando las columnas de
-- identidad. Un usuario normal solo puede editar wallet_usdt_erc20.

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
declare
  v_es_admin boolean := public.es_admin();
begin
  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  -- Identidad: lo que el admin ve en /usuarios, en la bandeja de soporte
  -- y en el CSV de reportes. Si el dueño de la fila lo puede reescribir,
  -- puede hacerse pasar por otra persona (o por el propio soporte)
  -- delante del admin, y falsear el conteo de referidos.
  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.invitado_por is distinct from old.invitado_por
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- Igual que con mensajes_soporte: el "with check" explícito evita que una
-- fila de `usuarios` se pueda mover fuera del alcance de la política.
drop policy if exists "cada usuario edita el suyo, admin edita cualquiera" on public.usuarios;

create policy "cada usuario edita el suyo, admin edita cualquiera"
  on public.usuarios for update
  using (auth.uid() = id or public.es_admin())
  with check (auth.uid() = id or public.es_admin());

-- ------------------------------------------------------------
-- 5) noticias.url_fuente: solo http/https
-- ------------------------------------------------------------
-- Se renderiza como href en la portada pública. "javascript:...",
-- "data:text/html,..." o "vbscript:..." ahí son XSS almacenado.

update public.noticias
set url_fuente = null
where url_fuente is not null
  and url_fuente !~* '^https?://[^[:space:]]+$';

alter table public.noticias
  drop constraint if exists noticias_url_fuente_http;

alter table public.noticias
  add constraint noticias_url_fuente_http check (
    url_fuente is null
    or url_fuente ~* '^https?://[^[:space:]]+$'
  );

-- ------------------------------------------------------------
-- 6) Límite de frecuencia en mensajes de soporte
-- ------------------------------------------------------------
-- mensajes_soporte es la única tabla donde un usuario normal puede
-- insertar filas sin pasar por un RPC, y no había ningún límite: un solo
-- usuario podía escribir mensajes de 2000 caracteres en bucle y llenar la
-- bandeja del admin (y la base) hasta hacerla inservible. El límite va en
-- la base, no en el server action, porque el insert se puede hacer también
-- directo con la anon key, y porque un contador en memoria de Next.js no
-- sirve cuando hay más de una instancia.

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  -- El admin responde muchas conversaciones seguidas: no se le limita.
  if public.es_admin() then
    return new;
  end if;

  select count(*) into v_recientes
  from public.mensajes_soporte
  where remitente_id = new.remitente_id
    and created_at > now() - interval '1 minute';

  if v_recientes >= 10 then
    raise exception 'Estás enviando mensajes demasiado rápido. Espera un momento antes de volver a escribir.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_insertar_mensaje_soporte on public.mensajes_soporte;
create trigger antes_de_insertar_mensaje_soporte
  before insert on public.mensajes_soporte
  for each row execute procedure public.limitar_frecuencia_mensajes_soporte();

revoke all on function public.limitar_frecuencia_mensajes_soporte()
  from public, anon, authenticated;

-- Índice para que ese count(*) no escanee la tabla entera a medida que el
-- historial de soporte crece.
create index if not exists mensajes_soporte_remitente_fecha
  on public.mensajes_soporte (remitente_id, created_at desc);

-- ------------------------------------------------------------
-- 7) favoritos: formato de símbolo y tope por usuario
-- ------------------------------------------------------------
-- El server action guardaba el símbolo tal cual llegaba del formulario,
-- sin formato ni cantidad máxima. Con la anon key se podía llenar la
-- tabla con texto arbitrario, y cada favorito se traduce en una petición
-- a Binance al renderizar /perfil: una lista inflada convierte una sola
-- visita en cientos de llamadas salientes y quema el límite de peticiones
-- de Binance, que es compartido por toda la plataforma.

delete from public.favoritos
where activo !~ '^[A-Z0-9]{5,20}$';

alter table public.favoritos
  drop constraint if exists favoritos_simbolo_formato;

alter table public.favoritos
  add constraint favoritos_simbolo_formato
  check (activo ~ '^[A-Z0-9]{5,20}$');

create or replace function public.limitar_favoritos_por_usuario()
returns trigger as $$
declare
  v_total int;
begin
  select count(*) into v_total
  from public.favoritos
  where usuario_id = new.usuario_id;

  if v_total >= 50 then
    raise exception 'Llegaste al máximo de 50 activos favoritos. Quita alguno antes de agregar otro.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_insertar_favorito on public.favoritos;
create trigger antes_de_insertar_favorito
  before insert on public.favoritos
  for each row execute procedure public.limitar_favoritos_por_usuario();

revoke all on function public.limitar_favoritos_por_usuario()
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- 8) "Cuenta desactivada" tiene que significar algo en la base
-- ------------------------------------------------------------
-- Hasta ahora, desactivar una cuenta solo la frenaba en el código de
-- Next.js: las páginas redirigen a /cuenta-desactivada y los server
-- actions llaman a exigirActivo(). Pero la sesión de Supabase sigue
-- siendo válida, y con la anon key se puede escribir directo saltándose
-- por completo los server actions. En la práctica un usuario baneado
-- podía seguir insertando mensajes en la bandeja de soporte.
-- es_admin() ya exige activo = true desde la migración 005; esto hace lo
-- propio para el usuario normal.

create or replace function public.cuenta_activa()
returns boolean as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and activo = true
  );
$$ language sql security definer stable set search_path = pg_catalog, public, pg_temp;

revoke all on function public.cuenta_activa() from public;
grant execute on function public.cuenta_activa() to anon, authenticated;

drop policy if exists "enviar mensaje propio, en conversacion propia o si es admin"
  on public.mensajes_soporte;

create policy "enviar mensaje propio, en conversacion propia o si es admin"
  on public.mensajes_soporte for insert
  with check (
    remitente_id = auth.uid()
    and public.cuenta_activa()
    and (usuario_id = auth.uid() or public.es_admin())
  );

-- Mismo criterio para los favoritos.
drop policy if exists "usuario agrega sus propios favoritos" on public.favoritos;

create policy "usuario agrega sus propios favoritos"
  on public.favoritos for insert
  with check (auth.uid() = usuario_id and public.cuenta_activa());

-- Y para abrir operaciones: abrir_operacion validaba trading_habilitado
-- pero no activo, así que una cuenta desactivada seguía siendo operable a
-- nivel de base. Se recrea la función de la migración 019 agregando ese
-- chequeo; todo lo demás queda idéntico.
create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric,
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;
  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.abrir_operacion(text, text, numeric, numeric, text)
  from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text)
  to authenticated;

-- ------------------------------------------------------------
-- 9) Quitar privilegios que PostgREST nunca usa
-- ------------------------------------------------------------
-- TRUNCATE no respeta RLS: con él, cualquier acceso SQL futuro con estos
-- roles podría vaciar las tablas de dinero saltándose todas las
-- políticas. TRIGGER y REFERENCES tampoco hacen falta para la API.

revoke truncate, trigger, references
  on public.usuarios, public.senales, public.noticias, public.config_portada,
     public.favoritos, public.saldo_virtual, public.operaciones_simuladas,
     public.pick_del_dia, public.mensajes_soporte, public.ganancias_concursos
  from anon, authenticated;

-- ============================================================
-- ROTACIÓN DEL SECRETO DE SERVIDOR
--
-- La migración 019 traía el valor real de `trading_server_secret` escrito
-- en texto plano, y este repositorio se entrega a terceros: hay que
-- considerarlo comprometido. Ese literal ya se quitó del archivo 019.
--
-- La rotación NO se escribe aquí a propósito (volvería a dejar el secreto
-- nuevo dentro de un archivo versionado). Se hace una sola vez, fuera de
-- git, con estos dos pasos:
--
--   1) Generar el valor:
--        node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
--   2) Guardarlo en LOS DOS lados:
--        · en .env.local (y en las variables de entorno del hosting)
--          como TRADING_SERVER_SECRET
--        · en la base, con:
--            update public.config_servidor
--            set valor = 'EL_VALOR_NUEVO', actualizado_en = now()
--            where clave = 'trading_server_secret';
--
-- Si los dos valores no coinciden, "Trade del día" y el cierre automático
-- de señales fallan a propósito (no se degradan en silencio).
-- ============================================================

-- Red de seguridad: si la fila no existe (instalación nueva), se crea con
-- un valor evidentemente inválido para que falle ruidosamente hasta que
-- alguien haga la rotación de arriba.
insert into public.config_servidor (clave, valor)
values ('trading_server_secret', 'FALTA-ROTAR-ESTE-SECRETO')
on conflict (clave) do nothing;
