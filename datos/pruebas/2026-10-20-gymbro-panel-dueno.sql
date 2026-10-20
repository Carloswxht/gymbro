-- Pruebas del panel del dueño (sobre replica-local + carpeta gymbro + datos de prueba de War300).
\set ON_ERROR_STOP 0
reset role;
update gymbro.socios_gymbro set rol = 'admin' where usuario_id = (select id from comun.usuarios where email = 'carloswxht+war300@gmail.com');
-- Otro gimnasio para comprobar que no se mezclan.
insert into comun.negocios (slug, nombre, tipo) values ('gym-otro', 'Gym otro ejemplo', 'gymbro') on conflict do nothing;
insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) select id, true from comun.negocios where slug = 'gym-otro' on conflict do nothing;
set role anon;
select entrar_gymbro('war300','carloswxht+war300@gmail.com','clave-prueba-1')->>'token' as ta \gset
select entrar_gymbro('war300','usuarioswxht@gmail.com','clave-prueba-1')->>'token' as tu \gset
select registrar_gymbro('gym-otro','otro@ejemplo.test','clave-otro-1','Otro') is not null as alta_otro;
select entrar_gymbro('gym-otro','otro@ejemplo.test','clave-otro-1')->>'token' as tx \gset
\echo '1. un socio no ve el panel (SIN_PERMISO)'
select panel_gymbro(:'tu');
\echo '2. el admin ve sus 2 socios y no los del otro gimnasio'
select jsonb_array_length(panel_gymbro(:'ta')->'socios') n, panel_gymbro(:'ta')->'negocio'->>'slug' slug;
\echo '3. alta de socio (y repetida: EMAIL_EN_USO; sin nombre: FALTAN_DATOS; correo de bar: EMAIL_EN_USO)'
select panel_alta_socio_gymbro(:'ta', 'Nuevo@Ejemplo.test', 'Socio nuevo')->>'email';
select panel_alta_socio_gymbro(:'ta', 'nuevo@ejemplo.test', 'Otra vez');
select panel_alta_socio_gymbro(:'ta', 'x@ejemplo.test', '  ');
select panel_alta_socio_gymbro(:'ta', 'camarero@ejemplo.test', 'Camarero');
select (x->>'pendiente')::boolean pendiente from jsonb_array_elements(panel_gymbro(:'ta')->'socios') x where x->>'email' = 'nuevo@ejemplo.test';
\echo '4. bienvenida: solo servidor; vale para el pendiente, no para quien ya tiene contraseña'
select bienvenida_crear_gymbro('nuevo@ejemplo.test');
reset role; set role service_role;
select (bienvenida_crear_gymbro('nuevo@ejemplo.test')->>'token') is not null as enlace_nuevo, bienvenida_crear_gymbro('usuarioswxht@gmail.com') is null as nada_para_antiguo;
reset role; set role anon;
\echo '5. dar de baja a un socio: ya no entra; reactivar'
reset role; select id as idu from comun.usuarios where email = 'usuarioswxht@gmail.com' \gset
set role anon;
select panel_estado_socio_gymbro(:'ta', :idu, false)->>'activo';
select entrar_gymbro('war300','usuarioswxht@gmail.com','clave-prueba-1')->>'error' sin_entrar;
select mis_datos_gymbro(:'tu') is not null as su_sesion_vale;
select panel_estado_socio_gymbro(:'ta', :idu, true)->>'activo';
\echo '6. no se puede dar de baja a sí mismo (NO_A_TI_MISMO) ni quitar el último admin (ULTIMO_ADMIN)'
reset role; select id as idc from comun.usuarios where email = 'carloswxht+war300@gmail.com' \gset
set role anon;
select panel_estado_socio_gymbro(:'ta', :idc, false);
select panel_rol_socio_gymbro(:'ta', :idc, 'socio');
\echo '7. hacer admin a otro y luego quitárselo; rol raro (ROL_NO_VALIDO)'
select panel_rol_socio_gymbro(:'ta', :idu, 'admin')->>'rol';
select panel_rol_socio_gymbro(:'ta', :idu, 'jefe');
select panel_rol_socio_gymbro(:'ta', :idu, 'socio')->>'rol';
\echo '8. no puede tocar a un socio de otro gimnasio ni a un camarero (USUARIO_NO_VALIDO x2)'
reset role; select id as idx from comun.usuarios where email = 'otro@ejemplo.test' \gset
set role anon;
select panel_estado_socio_gymbro(:'ta', :idx, false);
select panel_rol_socio_gymbro(:'ta', 1, 'admin');
\echo '9. registro libre: cerrar y abrir'
select panel_registro_gymbro(:'ta', false)->>'registro_abierto';
select registrar_gymbro('war300','cerrado@ejemplo.test','clave-xxx-1');
select panel_registro_gymbro(:'ta', true)->>'registro_abierto';
\echo '10. un admin de otro gimnasio no ve War300 (el panel solo muestra el suyo)'
reset role; update gymbro.socios_gymbro set rol = 'admin' where usuario_id = :idx; set role anon;
select panel_gymbro(:'tx')->'negocio'->>'slug' slug_otro, jsonb_array_length(panel_gymbro(:'tx')->'socios') n_otro;
reset role;
