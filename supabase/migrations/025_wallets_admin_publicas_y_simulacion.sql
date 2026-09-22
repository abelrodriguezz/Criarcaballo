-- ============================================================
-- MIGRACIÓN 025: wallets del admin visibles para el flujo de depósito
-- simulado (RPC de solo lectura, sin exponer el resto de la fila)
-- Pegar en Supabase → SQL Editor → Run (después de la migración 024)
-- ============================================================

-- Un usuario normal no tiene (ni debe tener) permiso para leer filas
-- ajenas de `usuarios`. Esta función expone SOLO las wallets del/los
-- admin(es), nunca su email ni ninguna otra columna — para que el botón
-- "Depositar (simulación)" del perfil normal pueda mostrar una al azar.
create or replace function public.obtener_wallets_admin()
returns text[] as $$
  select coalesce(array_remove(array_agg(w), null), array[]::text[])
  from (
    select wallet_usdt_erc20 as w from public.usuarios
      where role = 'admin' and wallet_usdt_erc20 is not null
    union all
    select wallet_usdt_erc20_2 from public.usuarios
      where role = 'admin' and wallet_usdt_erc20_2 is not null
    union all
    select wallet_usdt_erc20_3 from public.usuarios
      where role = 'admin' and wallet_usdt_erc20_3 is not null
  ) t;
$$ language sql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.obtener_wallets_admin() from public, anon;
grant execute on function public.obtener_wallets_admin() to authenticated;

-- El mensaje del cuadro de "esto es una simulación" reutiliza
-- config_portada (clave/valor genérico, ya usado para hero y nosotros)
-- bajo clave = 'simulacion_deposito' — no hace falta una tabla nueva.
