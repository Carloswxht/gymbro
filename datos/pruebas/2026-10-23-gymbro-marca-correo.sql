-- Pruebas de public.marca_correo_gymbro (23 oct 2026), sobre la base «login»
-- (datos/pruebas/montar-base-login.sh, que ya aplica el cambio). Las pruebas van en una transacción que se deshace.
-- Acaba en PRUEBAS_OK. Lanzar: psql … -d login -v ON_ERROR_STOP=1 -f este archivo
begin;

do $$
declare m jsonb; r jsonb;
begin
  -- 1. War300: logo de la web con dirección completa y colores del tema Original.
  m := public.marca_correo_gymbro((select id from comun.negocios where slug = 'war300'));
  if m is distinct from '{"logo":"https://gymbro.autonomialab.es/icons/icon-512.png","fondo":"#0E1013","acento":"#FF8A3D"}'::jsonb then
    raise exception '1 war300: %', m; end if;

  -- 2. Gimnasio sin aspecto ni logo: Original y el icono de Gymbro (como la app).
  m := public.marca_correo_gymbro((select id from comun.negocios where slug = 'gym-luna'));
  if m is distinct from '{"logo":"https://gymbro.autonomialab.es/icons/gymbro-512.png","fondo":"#0E1013","acento":"#FF8A3D"}'::jsonb then
    raise exception '2 luna: %', m; end if;

  -- 3. Tema Blanco y logo subido desde el móvil (data:): colores del tema, sin logo.
  update gymbro.ajustes_gymbro set aspecto = '{"tema":"theme-light"}', logo = 'data:image/png;base64,AAAA'
   where negocio_id = (select id from comun.negocios where slug = 'gym-luna');
  m := public.marca_correo_gymbro((select id from comun.negocios where slug = 'gym-luna'));
  if m is distinct from '{"fondo":"#FFFFFF","acento":"#FF6B1A"}'::jsonb then raise exception '3 blanco: %', m; end if;

  -- 4. Colores propios (en minúsculas): los suyos, en mayúsculas.
  update gymbro.ajustes_gymbro set aspecto = '{"tema":"propio","colores":{"ink":"#112233","day1":"#aabbcc","day2":"#000000","day3":"#FFFFFF"}}', logo = null
   where negocio_id = (select id from comun.negocios where slug = 'gym-luna');
  m := public.marca_correo_gymbro((select id from comun.negocios where slug = 'gym-luna'));
  if m->>'fondo' <> '#112233' or m->>'acento' <> '#AABBCC' then raise exception '4 propio: %', m; end if;

  -- 5. Tema que ya no existe: el Original.
  update gymbro.ajustes_gymbro set aspecto = '{"tema":"theme-viejo"}'
   where negocio_id = (select id from comun.negocios where slug = 'gym-luna');
  m := public.marca_correo_gymbro((select id from comun.negocios where slug = 'gym-luna'));
  if m->>'fondo' <> '#0E1013' then raise exception '5 tema viejo: %', m; end if;

  -- 6. Un bar o la plataforma: nada (no es de Gymbro). Negocio inexistente: nada.
  if public.marca_correo_gymbro((select id from comun.negocios where slug = 'bar-ejemplo')) is not null
     or public.marca_correo_gymbro((select id from comun.negocios where slug = 'autonomialab')) is not null
     or public.marca_correo_gymbro(9999) is not null then
    raise exception '6 otros negocios'; end if;

  -- 7. Por la común (lo que pide la Edge Function): socio de War300 con su nombre y colores.
  r := public.marca_correo((select auth_id from comun.usuarios where email = 'carloswxht+war300@gmail.com'));
  if r->>'marca' <> 'negocio' or r->>'producto' <> 'gymbro' or r->>'nombre' <> (select nombre from comun.negocios where slug = 'war300')
     or r->>'fondo' <> '#0E1013' or r->>'acento' <> '#FF8A3D' or r->>'logo' <> 'https://gymbro.autonomialab.es/icons/icon-512.png' then
    raise exception '7 común war300: %', r; end if;

  -- 8. La dueña de otro gimnasio recibe lo suyo, no lo de War300.
  r := public.marca_correo((select auth_id from comun.usuarios where email = 'luna@ejemplo.test'));
  if r->>'nombre' = (select nombre from comun.negocios where slug = 'war300') or r->>'fondo' <> '#0E1013' or r->>'logo' like '%icon-512%' then
    raise exception '8 común luna: %', r; end if;

  -- 9. La cuenta de plataforma: imagen de autonomIA Lab (no pasa por la de Gymbro).
  r := public.marca_correo((select auth_id from comun.usuarios where email = 'plataforma@ejemplo.test'));
  if r->>'marca' <> 'autonomialab' then raise exception '9 plataforma: %', r; end if;
end $$;

-- 10. La web (anon) y las cuentas (authenticated) no pueden llamarla; service_role sí.
do $$ begin
  if has_function_privilege('anon', 'public.marca_correo_gymbro(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.marca_correo_gymbro(integer)', 'execute')
     or not has_function_privilege('service_role', 'public.marca_correo_gymbro(integer)', 'execute') then
    raise exception '10 permisos'; end if;
end $$;

select 'PRUEBAS_OK' as resultado,
       md5(pg_get_functiondef('public.marca_correo_gymbro(integer)'::regprocedure)) as huella;
rollback;
