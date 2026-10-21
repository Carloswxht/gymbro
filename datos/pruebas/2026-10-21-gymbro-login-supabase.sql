-- Pruebas del login de Supabase de Gymbro (base local «login»: replica-local
-- + replica-auth + comun-cuentas-supabase + todos los datos/cambios +
-- datos-prueba-gymbro). En una transacción que se deshace al final.
-- «Entrar como» = poner el sub de su cuenta de Supabase, como hace Supabase.
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
reset role;
select auth_id as carlos from comun.usuarios where email = 'carloswxht+war300@gmail.com' \gset
select auth_id as socio  from comun.usuarios where email = 'usuarioswxht@gmail.com' \gset
select auth_id as luna   from comun.usuarios where email = 'luna@ejemplo.test' \gset
select auth_id as bar    from comun.usuarios where email = 'camarero@ejemplo.test' \gset
select auth_id as plat   from comun.usuarios where email = 'plataforma@ejemplo.test' \gset
select (select count(*) from gymbro.entrenos_gymbro e join comun.usuarios u on u.id = e.usuario_id where u.email = 'carloswxht+war300@gmail.com')
    || '/' || (select count(*) from gymbro.progreso_gymbro p join comun.usuarios u on u.id = p.usuario_id where u.email = 'carloswxht+war300@gmail.com') as antes \gset
\echo '1. sin sesión (anon) las funciones nuevas no existen para él (permiso denegado)'
set local role anon;
select yo_gymbro();
select mis_datos_gymbro();
select plataforma_gimnasios_gymbro();
reset role;
\echo '2. con sesión de una cuenta que no existe: SESION_CADUCADA'
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select yo_gymbro();
reset role;
\echo '3. Carlos: su gimnasio, sus entrenos y sus datos de siempre'
select set_config('request.jwt.claims', json_build_object('sub', :'carlos', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select y->>'email', y->>'rol', y->'negocio'->>'slug' from (select yo_gymbro() y) t;
select jsonb_array_length(mis_entrenos_gymbro()) entrenos, jsonb_array_length(mis_datos_gymbro()->'progreso') filas;
select guardar_progreso_gymbro('[{"work_key":"chk_prueba_login","peso":50}]'::jsonb) is not distinct from guardar_progreso_gymbro('[]'::jsonb) as guardado;
select legal_estado_gymbro()->>'aceptada' aceptada;
select (panel_gymbro()->'negocio'->>'slug') panel, jsonb_array_length(panel_gymbro()->'socios') socios;
\echo '4. Carlos no es plataforma: SESION_CADUCADA'
select plataforma_gimnasios_gymbro();
reset role;
\echo '5. socio sin permisos: su app sí (sin entrenos de Carlos), el panel no (SIN_PERMISO)'
select set_config('request.jwt.claims', json_build_object('sub', :'socio', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select jsonb_array_length(mis_entrenos_gymbro()) entrenos_suyos, (select count(*) from jsonb_array_elements(mis_datos_gymbro()->'progreso') x where x->>'work_key' = 'chk_prueba_login') ve_lo_de_carlos;
select panel_gymbro();
reset role;
\echo '6. la dueña de otro gimnasio solo ve el suyo'
select set_config('request.jwt.claims', json_build_object('sub', :'luna', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select panel_gymbro()->'negocio'->>'slug' su_panel, (select string_agg(x->>'email', ',') from jsonb_array_elements(panel_gymbro()->'socios') x) sus_socios;
reset role;
\echo '7. una cuenta de un bar no abre nada de Gymbro: SESION_CADUCADA (x3)'
select set_config('request.jwt.claims', json_build_object('sub', :'bar', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select yo_gymbro();
select panel_gymbro();
select plataforma_gimnasios_gymbro();
reset role;
\echo '8. la cuenta de plataforma: lista de gimnasios y su nombre; no es socia de ninguno'
select set_config('request.jwt.claims', json_build_object('sub', :'plat', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select string_agg(x->>'slug', ',' order by x->>'slug') gimnasios from jsonb_array_elements(plataforma_gimnasios_gymbro()) x;
select plataforma_yo_gymbro()->>'email';
select yo_gymbro();
reset role;
\echo '9. crear cuenta (registro libre): nace su cuenta de Supabase con la misma contraseña; cerrado, correo usado o de un bar no'
set local role anon;
select crear_cuenta_gymbro('gym-luna', ' Nueva@Ejemplo.test. ', 'clave-nueva-1')->>'email';
select crear_cuenta_gymbro('gym-sin', 'otra@ejemplo.test', 'clave-otra-1');
select crear_cuenta_gymbro('gym-luna', 'camarero@ejemplo.test', 'clave-otra-1');
select crear_cuenta_gymbro('bar-ejemplo', 'otra@ejemplo.test', 'clave-otra-1');
select crear_cuenta_gymbro('gym-luna', 'otra@ejemplo.test', 'corta');
reset role;
select au.encrypted_password = extensions.crypt('clave-nueva-1', au.encrypted_password) misma_clave, au.email
  from comun.usuarios u join auth.users au on au.id = u.auth_id where u.email = 'nueva@ejemplo.test';
select auth_id as nueva, id as id_nueva from comun.usuarios where email = 'nueva@ejemplo.test' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'nueva', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select yo_gymbro()->'negocio'->>'slug' su_gimnasio, yo_gymbro()->>'rol' rol;
reset role;
\echo '10. la dueña la da de baja: ya no entra y su cuenta de Supabase queda bloqueada'
select set_config('request.jwt.claims', json_build_object('sub', :'luna', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select panel_estado_socio_gymbro(:id_nueva, false)->>'activo';
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'nueva', 'role', 'authenticated')::text, true) is not null;
set local role authenticated;
select yo_gymbro();
reset role;
select banned_until > now() + interval '50 years' bloqueada from auth.users where id = :'nueva';
\echo '11. las funciones de antes (con token) siguen funcionando mientras tanto'
set local role anon;
select entrar_gymbro('war300', 'carloswxht+war300@gmail.com', 'clave-prueba-1')->>'token' as tk \gset
select jsonb_array_length(mis_entrenos_gymbro(:'tk')) entrenos_con_token;
reset role;
\echo '12. historial de Carlos igual que antes (entrenos/filas; +1 fila de la prueba 3)'
select :'antes' antes, (select count(*) from gymbro.entrenos_gymbro e join comun.usuarios u on u.id = e.usuario_id where u.email = 'carloswxht+war300@gmail.com')
    || '/' || (select count(*) from gymbro.progreso_gymbro p join comun.usuarios u on u.id = p.usuario_id where u.email = 'carloswxht+war300@gmail.com') despues;
rollback;
