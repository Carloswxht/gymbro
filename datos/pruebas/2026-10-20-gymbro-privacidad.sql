-- Pruebas de la privacidad de Gymbro (sobre replica-local + todos los
-- datos/cambios + datos de prueba de War300). En una transacción que se
-- deshace al final: se puede repetir.
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
reset role;
insert into comun.negocios (slug, nombre, tipo) values ('gym-otro', 'Gym otro ejemplo', 'gymbro');
insert into comun.usuarios (negocio_id,email,name,password_hash,must_change_password)
  select id,'otra@ejemplo.test','Otra',extensions.crypt('clave-otra-1',extensions.gen_salt('bf',4)),false from comun.negocios where slug='gym-otro';
insert into gymbro.socios_gymbro (usuario_id,negocio_id) select id,negocio_id from comun.usuarios where email='otra@ejemplo.test';
-- (otras pruebas cambian la contraseña de Carlos: se deja la de prueba)
update comun.usuarios set password_hash = extensions.crypt('clave-prueba-1', extensions.gen_salt('bf', 4)), failed_attempts = 0, locked_until = null
 where email = 'carloswxht+war300@gmail.com';
update comun.negocios set titular = null, nif = null, domicilio_fiscal = null, correo_legal = null, telefono_legal = null where slug = 'war300';
select id as iw from comun.negocios where slug = 'war300' \gset
select id as io from comun.negocios where slug = 'gym-otro' \gset
select id as ib from comun.negocios where slug = 'bar-ejemplo' \gset
set role anon;
select (plataforma_entrar('plataforma@ejemplo.test','clave-plataforma')->>'token') as tp \gset
select entrar_gymbro('war300','carloswxht+war300@gmail.com','clave-prueba-1')->>'token' as ta \gset
select entrar_gymbro('gym-otro','otra@ejemplo.test','clave-otra-1')->>'token' as tob \gset
\echo '1. página legal de War300 sin datos: incompleta; autonomIA Lab como encargado'
select l->>'version' version, l->>'completo' completo, l->'gimnasio'->>'nombre' gimnasio, l->'encargado'->>'nombre' encargado from (select legal_gymbro('war300') l) t;
\echo '2. legal de un bar o de un gimnasio que no existe: NEGOCIO_NO_VALIDO'
select legal_gymbro('bar-ejemplo');
select legal_gymbro('no-existe');
\echo '3. estado sin sesión: SESION_CADUCADA; con sesión: sin aceptar'
select legal_estado_gymbro('x');
select legal_estado_gymbro(:'ta')->>'aceptada';
\echo '4. aceptar una versión vieja (la primera, 2026-10-20) o inventada: VERSION_NO_VALIDA'
select aceptar_legal_gymbro(:'ta', '2026-10-20');
select aceptar_legal_gymbro(:'ta', '2020-01-01');
select aceptar_legal_gymbro(:'ta', null);
\echo '5. aceptar la vigente (dos veces no duplica); la otra socia sigue sin aceptar'
select aceptar_legal_gymbro(:'ta', '2026-10-20.2')->>'aceptada';
select aceptar_legal_gymbro(:'ta', '2026-10-20.2')->>'aceptada';
select legal_estado_gymbro(:'tob')->>'aceptada' otra_sin_aceptar;
reset role; select count(*) filas_carlos, min(negocio_id) = :iw negocio_bien from gymbro.consentimientos_gymbro where usuario_id = (select id from comun.usuarios where email = 'carloswxht+war300@gmail.com'); set role anon;
\echo '6. datos legales: sin plataforma (SESION_CADUCADA), bar (GIMNASIO_NO_VALIDO), NIF raro (DATOS_NO_VALIDOS), correo malo (EMAIL_NO_VALIDO)'
select plataforma_legal_gymbro(:'ta', :iw, '{"titular":"X"}');
select plataforma_legal_gymbro(:'tp', :ib, '{"titular":"X"}');
select plataforma_legal_gymbro(:'tp', :iw, '{"nif":"12<script>"}');
select plataforma_legal_gymbro(:'tp', :iw, '{"correo":"no-es-correo"}');
\echo '7. datos buenos (NIF con puntos y guiones, correo con punto del dictado): página completa; otro gimnasio no cambia'
select plataforma_legal_gymbro(:'tp', :iw, '{"titular":" Carlos Ejemplo ","nif":"12.345.678-z","domicilio":"Calle Mayor 1, 28001 Madrid","correo":"Hola@War300.test.","telefono":"600 000 000"}');
select legal_gymbro('war300')->>'completo' completo, legal_gymbro('gym-otro')->>'completo' otro;
select g->'legal'->>'nif' from (select plataforma_gimnasio_gymbro(:'tp', :iw) g) t;
\echo '8. vaciar un dato lo quita (vuelve a incompleta)'
select plataforma_legal_gymbro(:'tp', :iw, '{"titular":"Carlos Ejemplo","nif":"","domicilio":"Calle Mayor 1","correo":"hola@war300.test"}')->>'nif' nif;
select legal_gymbro('war300')->>'completo';
\echo '9. al borrar la cuenta se conserva la prueba del consentimiento'
select borrar_mi_cuenta_gymbro(:'ta', 'clave-prueba-1');
reset role; select count(*) consentimientos_tras_borrar from gymbro.consentimientos_gymbro c join comun.usuarios u on u.id = c.usuario_id where u.email like 'borrada-%'; set role anon;
\echo '10. la web (anon) no ve la tabla ni los ayudantes'
select * from gymbro.consentimientos_gymbro;
select privado.version_legal_gymbro();
reset role;
rollback;
