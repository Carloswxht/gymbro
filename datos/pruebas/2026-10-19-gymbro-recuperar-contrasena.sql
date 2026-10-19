-- Pruebas de recuperar la contraseña (sobre replica-local.sql + carpeta gymbro + datos de War300 de prueba).
\set ON_ERROR_STOP 0
\echo 'a. anon no puede crear enlaces (permiso denegado)'
set role anon; select recuperar_crear_gymbro('carloswxht+war300@gmail.com'); reset role;
\echo 'b. correo de bar o inexistente: null'
set role service_role; select recuperar_crear_gymbro('camarero@ejemplo.test') is null as nulo_bar, recuperar_crear_gymbro('nadie@x.es') is null as nulo_nadie;
select recuperar_crear_gymbro(' CARLOSWXHT+war300@gmail.com ')->>'token' as tk \gset
select recuperar_crear_gymbro('carloswxht+war300@gmail.com')->>'negocio_slug' slug; reset role;
\echo 'c. el primer enlace quedó anulado al pedir el segundo (ENLACE_NO_VALIDO)'
set role anon; select restablecer_gymbro(:'tk', 'nueva-clave-9');
reset role; set role service_role; select recuperar_crear_gymbro('carloswxht+war300@gmail.com')->>'token' as tk2 \gset
\echo 'd. 4.º enlace en una hora: null'
select recuperar_crear_gymbro('carloswxht+war300@gmail.com') is null as limite; reset role;
set role anon;
\echo 'e. contraseña corta (PASSWORD_CORTA) / buena / reutilizado (ENLACE_NO_VALIDO)'
select restablecer_gymbro(:'tk2', 'corta');
select restablecer_gymbro(:'tk2', 'nueva-clave-9');
select restablecer_gymbro(:'tk2', 'otra-clave-99');
\echo 'f. entra con la nueva y no con la vieja'
select entrar_gymbro('war300','carloswxht+war300@gmail.com','clave-prueba-1')->>'error' vieja, (entrar_gymbro('war300','carloswxht+war300@gmail.com','nueva-clave-9')->>'token') is not null nueva;
\echo 'g. un enlace de una cuenta de bar no vale aquí (ENLACE_NO_VALIDO)'
reset role; select privado.crear_enlace(1, 30) as tb \gset
set role anon; select restablecer_gymbro(:'tb', 'nueva-clave-9');
reset role;
