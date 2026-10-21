-- Datos de prueba de Gymbro (inventados; los reales no se guardan aquí).
-- War300 con Carlos (admin) y usuarioswxht (socio), los dos con «clave-prueba-1";
-- Carlos con su orden de días {1:2,2:1,3:3}, 3 entrenos y algún peso. Dos
-- gimnasios más: gym-luna (registro libre; dueña luna@ejemplo.test,
-- «clave-luna-1») y gym-sin (sin aspecto). Va después de todos los cambios.
insert into comun.negocios (slug, nombre, tipo) values ('war300','War300','gymbro'), ('gym-luna','Gym Luna','gymbro'), ('gym-sin','Gym Sin Aspecto','gymbro');
insert into comun.productos_contratados (negocio_id, producto) select id, 'gymbro' from comun.negocios where tipo = 'gymbro';
insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) select id, slug <> 'gym-sin' from comun.negocios where tipo = 'gymbro';
update gymbro.ajustes_gymbro a set aspecto = '{"lema": "La competencia es contra ti mismo.", "tema": "theme-dark"}', logo = '/icons/icon-512.png'
  from comun.negocios n where n.id = a.negocio_id and n.slug = 'war300';
insert into comun.usuarios (negocio_id, email, name, password_hash, must_change_password)
select n.id, v.e, v.nombre, extensions.crypt(v.c, extensions.gen_salt('bf', 4)), false
  from (values ('war300','carloswxht+war300@gmail.com','Carlos','clave-prueba-1'),
               ('war300','usuarioswxht@gmail.com','Usuario','clave-prueba-1'),
               ('gym-luna','luna@ejemplo.test','Dueña Luna','clave-luna-1')) v(slug, e, nombre, c)
  join comun.negocios n on n.slug = v.slug;
insert into gymbro.socios_gymbro (usuario_id, negocio_id, rol)
select u.id, u.negocio_id, case when u.email in ('carloswxht+war300@gmail.com','luna@ejemplo.test') then 'admin' else 'socio' end
  from comun.usuarios u join comun.negocios n on n.id = u.negocio_id where n.tipo = 'gymbro';
insert into gymbro.entrenos_gymbro (negocio_id, usuario_id, fecha, resumen, dia, tipo, created_at)
select u.negocio_id, u.id, d.f, '[{"exName":"Prueba","peso":40}]'::jsonb, d.dia, 'gym', d.c from comun.usuarios u,
 (values ('2026-10-13'::date, 2, '2026-10-13 15:48+00'::timestamptz), ('2026-10-13', 1, '2026-10-13 17:20+00'), ('2026-10-17', 3, '2026-10-17 16:15+00')) d(f, dia, c)
 where u.email = 'carloswxht+war300@gmail.com';
insert into gymbro.progreso_gymbro (negocio_id, usuario_id, work_key, reps, peso)
select negocio_id, id, k, r, p from comun.usuarios,
 (values ('__day_slots__', '{"1":2,"2":1,"3":3}', null::numeric), ('chk_pierna-y-core_cuadriceps_vastos::Sentadilla libre con barra', null, 40)) v(k, r, p)
 where email = 'carloswxht+war300@gmail.com';
insert into gymbro.consentimientos_gymbro (usuario_id, negocio_id, version)
select id, negocio_id, privado.version_legal_gymbro() from comun.usuarios where email = 'carloswxht+war300@gmail.com';
