-- ============================================================
-- MIGRACIÓN 080: cron real para el cierre automático de señales por TP/SL
-- Pegar en Supabase → SQL Editor → Run (después de 001-079)
--
-- Hasta ahora, revisarYCerrarSenalesActivas() (src/lib/senales/verificarTpSl.ts)
-- solo corría cuando alguien cargaba /senales (o su auto-refresh). El
-- resultado final siempre fue correcto (se revisan las velas históricas de
-- Binance desde que se publicó la señal, no el precio del momento), pero si
-- nadie visitaba la página, una señal que ya tocó su nivel se quedaba
-- "activa" en la UI hasta la próxima visita — podían pasar horas o días.
--
-- Mismo patrón que limpiar_comprobantes_vencidos() (migración 046):
-- pg_cron dispara una función SECURITY DEFINER que usa pg_net para llamar
-- por HTTP a la app real en Railway. Se llama a una ruta API nueva
-- (/api/cron/senales) que reutiliza la MISMA función de TypeScript que ya
-- usa /senales — no hay lógica de TP/SL duplicada en SQL.
--
-- El secreto para autenticar la llamada es el MISMO trading_server_secret
-- que ya vive en config_servidor (migración 019) — no hace falta agregar
-- ninguna variable de entorno nueva en Railway.
--
-- IMPORTANTE si el dominio cambia (ej. al conectar un dominio propio): hay
-- que actualizar la URL de esta función con
--   select cron.unschedule('cerrar-senales-automatico');
-- y volver a correr el bloque de abajo con la URL nueva.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.disparar_cron_senales()
returns void as $$
declare
  v_secreto text;
begin
  select valor into v_secreto
  from public.config_servidor
  where clave = 'trading_server_secret';

  if v_secreto is null or v_secreto = 'FALTA-ROTAR-ESTE-SECRETO' then
    raise notice 'trading_server_secret sin configurar todavia, se omite el cron de senales';
    return;
  end if;

  -- Encola la petición (asíncrono, no bloquea) — el cron no necesita
  -- esperar la respuesta, solo dispararla; la propia ruta hace el trabajo.
  perform net.http_post(
    url := 'https://criarcaballo-production.up.railway.app/api/cron/senales',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secreto,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.disparar_cron_senales() from public, anon, authenticated;

select cron.schedule(
  'cerrar-senales-automatico',
  '* * * * *', -- cada minuto; la propia app se auto-limita a revisar como mucho cada 30s
  $$select public.disparar_cron_senales()$$
);
