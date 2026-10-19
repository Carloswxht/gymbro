\set ON_ERROR_STOP 0
-- Dos negocios de Gymbro (A con registro abierto, B cerrado)
insert into comun.negocios (slug,nombre,tipo) values ('gym-a','Gym A ejemplo','gymbro'),('gym-b','Gym B ejemplo','gymbro');
insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) select id, slug='gym-a' from comun.negocios where tipo='gymbro';
set role anon;
\echo '1. registro en A (debe dar token)'
select (registrar_gymbro('gym-a','Ana@Ejemplo.test','clave-ana-1','Ana')->>'token') is not null as ok;
\echo '2. registro en B cerrado (REGISTRO_CERRADO)'
select registrar_gymbro('gym-b','b@ejemplo.test','clave-b-12');
\echo '3. correo ya usado por un camarero (EMAIL_EN_USO)'
select registrar_gymbro('gym-a','camarero@ejemplo.test','clave-xxx-1');
\echo '4. slug de un bar (NEGOCIO_NO_VALIDO)'
select registrar_gymbro('bar-ejemplo','x@ejemplo.test','clave-xxx-1');
\echo '5. leer tablas directamente (permiso denegado)'
select * from gymbro.progreso_gymbro;
select * from comun.usuarios;
\echo '6. ayudante privado (permiso denegado)'
select privado.abrir_sesion_gymbro(1);
reset role;
\set ON_ERROR_STOP 0
-- Socio en B dado de alta a mano (como hará la copia de War300), con hash bcrypt $2a$
insert into comun.usuarios (negocio_id,email,name,password_hash,must_change_password)
  select id,'beto@ejemplo.test','Beto',extensions.crypt('clave-beto-1',extensions.gen_salt('bf',10)),false from comun.negocios where slug='gym-b';
insert into gymbro.socios_gymbro (usuario_id,negocio_id) select u.id,u.negocio_id from comun.usuarios u where email='beto@ejemplo.test';
set role anon;
\echo '7. entrar Ana en A'
select entrar_gymbro('gym-a','ana@ejemplo.test','clave-ana-1')->>'token' as ta \gset
select length(:'ta') = 64 as ok;
\echo '8. Ana intenta entrar por B (CREDENCIALES)'
select entrar_gymbro('gym-b','ana@ejemplo.test','clave-ana-1');
\echo '9. Ana en MultiBar y en plataforma (CREDENCIALES x2)'
select personal_entrar('ana@ejemplo.test','clave-ana-1'); select plataforma_entrar('ana@ejemplo.test','clave-ana-1');
\echo '10. camarero en Gymbro (CREDENCIALES); su token no vale en Gymbro (SESION_CADUCADA)'
select entrar_gymbro('gym-a','camarero@ejemplo.test','clave-camarero');
select personal_entrar('camarero@ejemplo.test','clave-camarero')->>'token' as tc \gset
select mis_datos_gymbro(:'tc');
select plataforma_entrar('plataforma@ejemplo.test','clave-plataforma')->>'token' as tp \gset
select mis_datos_gymbro(:'tp');
\echo '11. guardar progreso parcial y leer'
select guardar_progreso_gymbro(:'ta', '[{"work_key":"press","peso":"60","series":"4","reps":"10"},{"work_key":"__theme__","series":"neon"}]');
select guardar_progreso_gymbro(:'ta', '{"work_key":"press","checked":true}');
select mis_datos_gymbro(:'ta')->'progreso';
\echo '12. datos malos (DATOS_NO_VALIDOS x2)'
select guardar_progreso_gymbro(:'ta', '[{"work_key":"x","peso":"abc"}]');
select guardar_progreso_gymbro(:'ta', '[{"peso":"1"}]');
\echo '13. entrenos y personalizados'
select guardar_entreno_gymbro(:'ta', current_date, '{"ej":1}', 2) is not null as ok;
select guardar_entreno_gymbro(:'ta', current_date, '{}', null, 'casa') is not null as ok;
select guardar_entreno_gymbro(:'ta', current_date, '{}', null, 'otro');
select jsonb_array_length(mis_entrenos_gymbro(:'ta')) as entrenos_ana;
select guardar_personalizado_gymbro(:'ta','pecho','Fondos','https://ejemplo.test/v.mp4')->>'nombre';
select guardar_personalizado_gymbro(:'ta','pecho','Mal','javascript:alert(1)');
\echo '14. Beto entra en B (hash de fuera) y no ve nada de Ana'
select entrar_gymbro('gym-b','beto@ejemplo.test','clave-beto-1')->>'token' as tb \gset
select mis_datos_gymbro(:'tb') as datos_beto, mis_entrenos_gymbro(:'tb') as entrenos_beto;
\echo '15. yo, cambiar contraseña, salir'
select yo_gymbro(:'ta')->>'nombre', yo_gymbro(:'ta')->'negocio'->>'slug';
select cambiar_password_gymbro(:'ta','mala','nueva-clave-1');
select cambiar_password_gymbro(:'ta','clave-ana-1','nueva-clave-1');
select (entrar_gymbro('gym-a','ana@ejemplo.test','nueva-clave-1')->>'token') is not null as nueva_ok;
select salir_gymbro(:'ta'); select yo_gymbro(:'ta');
\echo '16. salir_gymbro con token de camarero no le cierra la sesión'
select salir_gymbro(:'tc');
reset role;
select count(*) as sesion_camarero_sigue from comun.sesiones where token_hash = extensions.digest(:'tc','sha256');
set role anon;
\echo '17. bloqueo tras 5 fallos'
select entrar_gymbro('gym-b','beto@ejemplo.test','x') from generate_series(1,5);
select entrar_gymbro('gym-b','beto@ejemplo.test','clave-beto-1');
reset role; update comun.usuarios set locked_until=null, failed_attempts=0 where email='beto@ejemplo.test'; set role anon;
\echo '18. borrar cuenta de Beto'
select borrar_mi_cuenta_gymbro(:'tb','mala');
select borrar_mi_cuenta_gymbro(:'tb','clave-beto-1');
select entrar_gymbro('gym-b','beto@ejemplo.test','clave-beto-1');
reset role;
select email, name, active from comun.usuarios order by id;
\echo '19. un negocio de baja no deja entrar'
update comun.negocios set activo=false where slug='gym-a';
set role anon; select entrar_gymbro('gym-a','ana@ejemplo.test','nueva-clave-1'); reset role;
