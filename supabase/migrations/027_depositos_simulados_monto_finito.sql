-- ============================================================
-- MIGRACIÓN 027: el monto del depósito simulado tiene que ser un número
-- de verdad (ni NaN ni Infinity ni 400 dígitos)
-- Pegar en Supabase → SQL Editor → Run (después de 001-026)
--
-- El `check (monto > 0)` de la migración 026 NO alcanzaba: en Postgres el
-- tipo numeric admite los valores especiales 'NaN' e 'Infinity', y ambos
-- pasan la comparación (NaN se ordena por encima de cualquier número, así
-- que 'NaN' > 0 es TRUE). Cualquier usuario autenticado podía insertar
-- {"monto": "NaN"} llamando a la API directamente (sin pasar por el
-- formulario) y PostgREST devolvía ese monto como string. En el cliente,
-- monto.toFixed(2) sobre un string lanza un TypeError: eso tumbaba con un
-- 500 la página /usuarios del admin — y el admin quedaba sin manera de
-- borrar la fila, porque la propia pantalla que tiene el botón Eliminar ya
-- no cargaba. También hacía caer el /perfil del propio usuario.
--
-- Arreglo: numeric(14,2) (montos de dinero, con la escala fija) y un check
-- con tope superior. El tope es lo que descarta NaN e Infinity, porque
-- `NaN <= 100000000` es FALSE. El código además ya no usa .toFixed sobre
-- este valor, así que quedan las dos capas.
-- ============================================================

-- Por si quedara alguna fila envenenada de antes: el cast a numeric(14,2)
-- fallaría con Infinity, y el check nuevo no se podría crear con NaN.
delete from public.depositos_simulados
where monto is null
   or not (monto > 0 and monto <= 100000000);

alter table public.depositos_simulados
  drop constraint depositos_simulados_monto_check;

alter table public.depositos_simulados
  alter column monto type numeric(14, 2);

alter table public.depositos_simulados
  add constraint depositos_simulados_monto_check
  check (monto > 0 and monto <= 100000000);

-- wallet_mostrada la manda el propio cliente, así que por API directa
-- acepta cualquier texto de cualquier tamaño (se probó guardando 200 KB en
-- una sola fila). Hoy no se muestra en ninguna pantalla, así que no hay
-- XSS posible, pero es una columna de texto libre sin tope: se limita al
-- largo de una dirección ERC-20 con margen.
alter table public.depositos_simulados
  add constraint depositos_simulados_wallet_mostrada_check
  check (wallet_mostrada is null or length(wallet_mostrada) <= 120);
