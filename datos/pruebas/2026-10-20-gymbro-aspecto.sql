-- Pruebas del aspecto de cada gimnasio (sobre replica-local + todos los
-- datos/cambios + datos de prueba de War300). Todo dentro de una transacción
-- que se deshace al final: se puede repetir.
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
reset role;
insert into comun.negocios (slug, nombre, tipo) values ('gym-otro', 'Gym otro ejemplo', 'gymbro');
select id as iw from comun.negocios where slug = 'war300' \gset
select id as io from comun.negocios where slug = 'gym-otro' \gset
select id as ib from comun.negocios where slug = 'bar-ejemplo' \gset
set role anon;
select (plataforma_entrar('plataforma@ejemplo.test','clave-plataforma')->>'token') as tp \gset
select entrar_gymbro('war300','carloswxht+war300@gmail.com','clave-prueba-1')->>'token' as ta \gset
\echo '1. War300 conserva lo de antes: lema, tema Original y su icono (logo_v sin el logo dentro)'
select n->>'nombre' nombre, n->'aspecto' aspecto, n->>'logo_v' is not null con_logo, n ? 'logo_gymbro' no_debe from (select negocio_gymbro('war300') n) t;
select logo_gymbro('war300');
\echo '2. un gimnasio sin aspecto (sin ajustes): aspecto vacío, sin logo'
select negocio_gymbro('gym-otro');
select logo_gymbro('gym-otro');
\echo '3. logo de un bar o de un gimnasio que no existe: NEGOCIO_NO_VALIDO'
select logo_gymbro('bar-ejemplo');
select logo_gymbro('no-existe');
\echo '4. sin sesión de plataforma (token falso o admin de gimnasio): SESION_CADUCADA'
select plataforma_aspecto_gymbro('x', :io, '{"nombre":"X"}');
select plataforma_aspecto_gymbro(:'ta', :iw, '{"nombre":"Hackeado"}');
select plataforma_logo_gymbro(:'ta', :iw, null);
\echo '5. errores: bar (GIMNASIO_NO_VALIDO), sin nombre (FALTAN_DATOS), lema largo, tema raro, colores malos (DATOS_NO_VALIDOS)'
select plataforma_aspecto_gymbro(:'tp', :ib, '{"nombre":"Bar"}');
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"  "}');
select plataforma_aspecto_gymbro(:'tp', :io, jsonb_build_object('nombre','Gym', 'lema', repeat('x', 81)));
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"Gym","tema":"<script>"}');
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"Gym","tema":"propio","colores":{"ink":"#000","day1":"#FF0000","day2":"#00FF00","day3":"#0000FF"}}');
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"Gym","tema":"propio"}');
\echo '6. guardar con colores propios (se guardan en mayúsculas; lo desconocido se descarta)'
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":" Gym Otro ","lema":" Entrena duro. ","tema":"propio","colores":{"ink":"#101010","day1":"#ff0000","day2":"#00ff00","day3":"#0000ff"},"raro":1}')->'aspecto';
select negocio_gymbro('gym-otro')->>'nombre';
\echo '7. guardar con un tema de la app y sin lema (el lema se quita)'
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"Gym Otro","tema":"theme-neon"}')->'aspecto';
\echo '8. logo: ruta mala, tipo malo, demasiado grande (LOGO_NO_VALIDO)'
select plataforma_logo_gymbro(:'tp', :io, '/../secreto.png');
select plataforma_logo_gymbro(:'tp', :io, 'data:image/svg+xml;base64,PHN2Zz4=');
select plataforma_logo_gymbro(:'tp', :io, 'data:image/png;base64,' || repeat('A', 400000));
select plataforma_logo_gymbro(:'tp', :ib, '/icons/icon-512.png');
\echo '9. logo bueno: la huella cambia y la app lo puede leer; la ficha lo trae'
select plataforma_logo_gymbro(:'tp', :io, 'data:image/png;base64,iVBORw0KGgo=')->>'logo_v' as hv \gset
select :'hv' = negocio_gymbro('gym-otro')->>'logo_v' misma_huella, :'hv' <> negocio_gymbro('war300')->>'logo_v' distinta_de_war300;
select logo_gymbro('gym-otro')->>'logo';
select g->>'logo_gymbro', g->'aspecto'->>'tema' from (select plataforma_gimnasio_gymbro(:'tp', :io) g) t;
\echo '10. quitar el logo; War300 no se ha tocado'
select plataforma_logo_gymbro(:'tp', :io, null);
select negocio_gymbro('gym-otro')->>'logo_v' is null sin_logo, negocio_gymbro('war300')->'aspecto' war300, logo_gymbro('war300')->>'logo' logo_war300;
\echo '11. de baja: la app no lee su logo (NEGOCIO_NO_VALIDO), la plataforma sí lo puede cambiar'
select plataforma_estado_gimnasio_gymbro(:'tp', :io, false)->>'activo';
select logo_gymbro('gym-otro');
select plataforma_aspecto_gymbro(:'tp', :io, '{"nombre":"Gym Otro"}')->>'nombre';
\echo '12. la web (anon) no ve el ayudante ni la tabla'
select privado.aspecto_limpio_gymbro('{}');
select logo from gymbro.ajustes_gymbro;
reset role;
rollback;
