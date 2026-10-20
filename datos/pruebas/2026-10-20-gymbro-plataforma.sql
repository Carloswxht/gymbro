-- Pruebas del panel de plataforma de Gymbro (sobre replica-local + carpeta gymbro
-- + panel del dueño + plataforma + datos de prueba de War300). Todo dentro de una
-- transacción que se deshace al final: se puede repetir.
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
reset role;
insert into comun.negocios (slug, nombre, tipo) values ('gym-otro', 'Gym otro ejemplo', 'gymbro') on conflict do nothing;
set role anon;
select (plataforma_entrar('plataforma@ejemplo.test','clave-plataforma')->>'token') as tp \gset
select entrar_gymbro('war300','carloswxht+war300@gmail.com','clave-prueba-1')->>'token' as ta \gset
select personal_entrar('camarero@ejemplo.test','clave-camarero')->>'token' as tb \gset
\echo '1. sin sesión de plataforma: SESION_CADUCADA (token falso, admin de gimnasio y camarero)'
select plataforma_gimnasios_gymbro('x');
select plataforma_gimnasios_gymbro(:'ta');
select plataforma_gimnasios_gymbro(:'tb');
\echo '2. la lista solo tiene gimnasios (war300 y gym-otro, no bares ni la plataforma)'
select string_agg(x->>'slug', ',' order by x->>'slug') from jsonb_array_elements(plataforma_gimnasios_gymbro(:'tp')) x;
select x->'cifras' from jsonb_array_elements(plataforma_gimnasios_gymbro(:'tp')) x where x->>'slug' = 'war300';
\echo '3. ficha de War300 (con su admin) y de un bar (GIMNASIO_NO_VALIDO)'
reset role; select id as iw from comun.negocios where slug = 'war300' \gset
select id as ib from comun.negocios where slug = 'bar-ejemplo' \gset
set role anon;
select g->>'slug', g->>'registro_abierto', jsonb_array_length(g->'admins') admins, g->'admins'->0->>'email' from (select plataforma_gimnasio_gymbro(:'tp', :iw) g) t;
select plataforma_gimnasio_gymbro(:'tp', :ib);
\echo '4. alta de gimnasio: errores (FALTAN_DATOS, SLUG_NO_VALIDO x2, SLUG_EN_USO, EMAIL_NO_VALIDO, EMAIL_EN_USO)'
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"","slug":"gym-nuevo","email":"d@ejemplo.test"}');
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym","slug":"Gym Nuevo","email":"d@ejemplo.test"}');
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym","slug":"panel","email":"d@ejemplo.test"}');
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym","slug":"bar-ejemplo","email":"d@ejemplo.test"}');
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym","slug":"gym-nuevo","email":"no-es-correo"}');
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym","slug":"gym-nuevo","email":"camarero@ejemplo.test"}');
select plataforma_alta_gimnasio_gymbro(:'ta', '{"nombre":"Gym","slug":"gym-nuevo","email":"d@ejemplo.test"}');
\echo '5. alta buena (correo con punto final y mayúsculas): negocio, contratado, ajustes y dueño admin pendiente'
select plataforma_alta_gimnasio_gymbro(:'tp', '{"nombre":"Gym Nuevo","slug":"gym-nuevo","email":"Dueno@Ejemplo.test.","dueno":"Dueña"}')->>'email';
reset role;
select n.tipo, n.activo, pc.producto, a.registro_abierto, u.name, u.must_change_password, so.rol
  from comun.negocios n join comun.productos_contratados pc on pc.negocio_id = n.id
  join gymbro.ajustes_gymbro a on a.negocio_id = n.id
  join comun.usuarios u on u.negocio_id = n.id join gymbro.socios_gymbro so on so.usuario_id = u.id
 where n.slug = 'gym-nuevo';
select id as ig from comun.negocios where slug = 'gym-nuevo' \gset
\echo '6. el dueño recibe la bienvenida (solo servidor), elige contraseña, entra y ve su panel'
set role service_role;
select b->>'token' as tk, b->>'negocio_slug' as slug_enlace from (select bienvenida_crear_gymbro('dueno@ejemplo.test') b) t \gset
\echo enlace al gimnasio: :slug_enlace
set role anon;
select restablecer_gymbro(:'tk', 'clave-duena-1') is not null as restablecida;
select entrar_gymbro('gym-nuevo','dueno@ejemplo.test','clave-duena-1')->>'token' as td \gset
select panel_gymbro(:'td')->'negocio'->>'slug' su_gimnasio, jsonb_array_length(panel_gymbro(:'td')->'socios') socios;
select entrar_gymbro('war300','dueno@ejemplo.test','clave-duena-1')->>'error' no_entra_en_war300;
\echo '7. registro libre del gimnasio nuevo: apagado; encender y apagar; en un bar no (GIMNASIO_NO_VALIDO)'
select registrar_gymbro('gym-nuevo','socio@ejemplo.test','clave-socio-1');
select plataforma_registro_gymbro(:'tp', :ig, true)->>'registro_abierto';
select registrar_gymbro('gym-nuevo','socio@ejemplo.test','clave-socio-1')->>'token' is not null as alta_socio;
select plataforma_registro_gymbro(:'tp', :ig, false)->>'registro_abierto';
select plataforma_registro_gymbro(:'tp', :ib, true);
\echo '8. dar de baja el gimnasio: nadie entra ni su sesión vale; reactivar'
select plataforma_estado_gimnasio_gymbro(:'tp', :ig, false)->>'activo';
select entrar_gymbro('gym-nuevo','dueno@ejemplo.test','clave-duena-1');
select panel_gymbro(:'td');
select (x->>'activo') from jsonb_array_elements(plataforma_gimnasios_gymbro(:'tp')) x where x->>'slug' = 'gym-nuevo';
select plataforma_estado_gimnasio_gymbro(:'tp', :ig, true)->>'activo';
select panel_gymbro(:'td')->'negocio'->>'slug' vuelve;
select plataforma_estado_gimnasio_gymbro(:'tp', :ib, false);
reset role;
select activo from comun.negocios where id = :ib;
\echo '9. War300 sigue igual (socios y entrenos)'
set role anon;
select x->'cifras'->>'entrenos_30d' is not null, x->>'activo' from jsonb_array_elements(plataforma_gimnasios_gymbro(:'tp')) x where x->>'slug' = 'war300';
\echo '10. la web no puede llamar a los ayudantes'
select privado.cifras_gimnasio_gymbro(1);
reset role;
rollback;
