-- =====================================================================
-- Gymbro · paso 1: carpeta `gymbro` en autonomialab-db (19 oct 2026)
-- =====================================================================
-- Solo AÑADE cosas nuevas. No cambia ni borra nada de `comun` ni de
-- `multibar`: La Mar de Gambas no nota nada.
--
-- Cuentas: Gymbro usa las mismas tablas de cuentas que todos
-- (comun.usuarios, comun.sesiones, comun.recuperaciones), con la misma
-- forma de cifrar contraseñas. Pero las funciones de entrar de MultiBar
-- (personal_entrar…) solo buscan personal de bares, así que Gymbro trae
-- las suyas (entrar_gymbro…). Cada cuenta es de un único negocio: una
-- cuenta de Gymbro solo abre funciones de Gymbro y de su negocio.
--
-- Tablas cerradas a la web; la web solo llama a las funciones de `public`
-- terminadas en _gymbro. Se puede volver a ejecutar sin romper nada.
-- =====================================================================

begin;

create schema if not exists gymbro;
revoke all on schema gymbro from public, anon, authenticated;

-- Ajustes de cada negocio de Gymbro (su personalización y sus opciones).
create table if not exists gymbro.ajustes_gymbro (
  negocio_id       int primary key references comun.negocios(id),
  registro_abierto boolean not null default false,   -- la gente se crea la cuenta sola
  aspecto          jsonb   not null default '{}'::jsonb,  -- colores, logo, textos
  opciones         jsonb   not null default '{}'::jsonb,
  updated_at       timestamptz not null default now()
);

-- Quién es socio (o admin) de cada negocio de Gymbro.
create table if not exists gymbro.socios_gymbro (
  usuario_id int primary key references comun.usuarios(id),
  negocio_id int not null references comun.negocios(id),
  rol        text not null default 'socio' check (rol in ('socio', 'admin')),
  created_at timestamptz not null default now()
);
create index if not exists socios_gymbro_negocio_idx on gymbro.socios_gymbro (negocio_id);

-- Rutina y progreso de cada persona (antes «progreso» en War300).
create table if not exists gymbro.progreso_gymbro (
  id                uuid primary key default gen_random_uuid(),
  negocio_id        int  not null references comun.negocios(id),
  usuario_id        int  not null references comun.usuarios(id),
  work_key          text not null check (length(work_key) between 1 and 200),
  peso              numeric check (peso is null or (peso >= 0 and peso < 10000)),
  series            text check (length(series) <= 2000),
  reps              text check (length(reps) <= 20000),
  checked           boolean not null default false,
  ejercicio_elegido text check (length(ejercicio_elegido) <= 200),
  updated_at        timestamptz not null default now(),
  unique (usuario_id, work_key)
);

-- Entrenos terminados (antes «sesiones» en War300).
create table if not exists gymbro.entrenos_gymbro (
  id         uuid primary key default gen_random_uuid(),
  negocio_id int  not null references comun.negocios(id),
  usuario_id int  not null references comun.usuarios(id),
  fecha      date not null default current_date,
  resumen    jsonb not null check (length(resumen::text) <= 100000),
  dia        int check (dia is null or dia between 1 and 7),
  tipo       text not null default 'gym' check (tipo in ('gym', 'casa')),
  created_at timestamptz not null default now()
);
create index if not exists entrenos_gymbro_usuario_idx on gymbro.entrenos_gymbro (usuario_id, fecha);

-- Ejercicios que cada persona añade a mano.
create table if not exists gymbro.ejercicios_personalizados_gymbro (
  id         uuid primary key default gen_random_uuid(),
  negocio_id int  not null references comun.negocios(id),
  usuario_id int  not null references comun.usuarios(id),
  sub_id     text not null check (length(sub_id) between 1 and 100),
  nombre     text not null check (length(nombre) between 1 and 100),
  video_url  text check (video_url is null or (length(video_url) <= 500 and video_url ~ '^https://')),
  created_at timestamptz not null default now()
);
create index if not exists ejercicios_personalizados_gymbro_usuario_idx
  on gymbro.ejercicios_personalizados_gymbro (usuario_id);

alter table gymbro.ajustes_gymbro                   enable row level security;
alter table gymbro.socios_gymbro                    enable row level security;
alter table gymbro.progreso_gymbro                  enable row level security;
alter table gymbro.entrenos_gymbro                  enable row level security;
alter table gymbro.ejercicios_personalizados_gymbro enable row level security;
revoke all on all tables in schema gymbro from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Ayudantes (en `privado`, no se ven desde la web)
-- ---------------------------------------------------------------------

-- Negocio de Gymbro activo a partir de su slug.
create or replace function privado.negocio_gymbro(p_slug text)
returns comun.negocios
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  select * into n from comun.negocios
   where slug = lower(btrim(coalesce(p_slug, ''))) and tipo = 'gymbro' and activo;
  if not found then
    raise exception 'NEGOCIO_NO_VALIDO';
  end if;
  return n;
end $$;

-- Socio a partir de su sesión. Solo vale una sesión de una cuenta activa,
-- de un negocio de Gymbro activo y dada de alta en socios_gymbro.
create or replace function privado.socio_de_token_gymbro(p_token text)
returns gymbro.socios_gymbro
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'SESION_CADUCADA';
  end if;
  select so.* into s
    from comun.sesiones se
    join comun.usuarios us   on us.id = se.usuario_id
    join gymbro.socios_gymbro so on so.usuario_id = us.id and so.negocio_id = us.negocio_id
    join comun.negocios n    on n.id = us.negocio_id
   where se.token_hash = privado.digest(p_token, 'sha256')
     and se.expires_at > now()
     and us.active and n.activo and n.tipo = 'gymbro';
  if not found then
    raise exception 'SESION_CADUCADA';
  end if;
  return s;
end $$;

-- Lo que la app necesita saber del negocio (nombre, logo, aspecto, registro).
create or replace function privado.negocio_json_gymbro(p_negocio int)
returns jsonb
language sql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
  select jsonb_build_object(
    'slug', n.slug, 'nombre', n.nombre, 'logo', n.logo,
    'aspecto', coalesce(a.aspecto, '{}'::jsonb),
    'registro_abierto', coalesce(a.registro_abierto, false))
    from comun.negocios n left join gymbro.ajustes_gymbro a on a.negocio_id = n.id
   where n.id = p_negocio
$$;

-- Abre una sesión larga (en el gimnasio no se quiere entrar cada día).
create or replace function privado.abrir_sesion_gymbro(p_usuario int)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare v_token text; u comun.usuarios; s gymbro.socios_gymbro;
begin
  select * into u from comun.usuarios where id = p_usuario;
  select * into s from gymbro.socios_gymbro where usuario_id = p_usuario;
  delete from comun.sesiones where usuario_id = p_usuario and expires_at < now();
  v_token := encode(privado.gen_random_bytes(32), 'hex');
  insert into comun.sesiones (token_hash, usuario_id, expires_at)
  values (privado.digest(v_token, 'sha256'), p_usuario, now() + interval '60 days');
  return jsonb_build_object('token', v_token, 'id', u.id, 'nombre', u.name, 'email', u.email,
                            'rol', s.rol, 'cambiar_password', u.must_change_password,
                            'negocio', privado.negocio_json_gymbro(u.negocio_id));
end $$;

-- ---------------------------------------------------------------------
-- Funciones que llama la web (public, terminadas en _gymbro)
-- ---------------------------------------------------------------------

-- Datos públicos del negocio para pintar la pantalla de entrar.
create or replace function public.negocio_gymbro(p_slug text)
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
begin
  return privado.negocio_json_gymbro((privado.negocio_gymbro(p_slug)).id);
end $$;

-- Crear cuenta (solo si el negocio tiene el registro abierto).
create or replace function public.registrar_gymbro(p_slug text, p_email text, p_password text, p_nombre text default null)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; v_email text; v_nombre text; v_id int;
begin
  n := privado.negocio_gymbro(p_slug);
  if not coalesce((select registro_abierto from gymbro.ajustes_gymbro where negocio_id = n.id), false) then
    raise exception 'REGISTRO_CERRADO';
  end if;
  v_email := lower(btrim(coalesce(p_email, '')));
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' or length(v_email) > 254 then
    raise exception 'EMAIL_NO_VALIDO';
  end if;
  if length(coalesce(p_password, '')) < 8 or length(p_password) > 72 then
    raise exception 'PASSWORD_CORTA';
  end if;
  v_nombre := left(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g')), 60);
  if v_nombre = '' then
    v_nombre := split_part(v_email, '@', 1);
  end if;
  -- Freno contra altas masivas: como mucho 30 cuentas nuevas por hora en cada negocio.
  if (select count(*) from gymbro.socios_gymbro
       where negocio_id = n.id and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'DEMASIADOS_INTENTOS';
  end if;
  if exists (select 1 from comun.usuarios where lower(email) = v_email) then
    raise exception 'EMAIL_EN_USO';
  end if;
  insert into comun.usuarios (negocio_id, email, name, password_hash, must_change_password)
  values (n.id, v_email, v_nombre, privado.crypt(p_password, privado.gen_salt('bf', 10)), false)
  returning id into v_id;
  insert into gymbro.socios_gymbro (usuario_id, negocio_id, rol) values (v_id, n.id, 'socio');
  return privado.abrir_sesion_gymbro(v_id);
end $$;

-- Entrar. Solo encuentra cuentas de ese negocio de Gymbro.
create or replace function public.entrar_gymbro(p_slug text, p_email text, p_password text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; u comun.usuarios;
begin
  n := privado.negocio_gymbro(p_slug);
  select us.* into u
    from comun.usuarios us join gymbro.socios_gymbro so on so.usuario_id = us.id
   where lower(us.email) = lower(btrim(coalesce(p_email, ''))) and us.negocio_id = n.id
     for update of us;
  if not found then
    -- Mismo trabajo que con una cuenta real, para no revelar qué correos existen.
    perform privado.crypt(coalesce(p_password, ''), privado.gen_salt('bf', 10));
    return jsonb_build_object('error', 'CREDENCIALES');
  end if;
  if u.locked_until is not null and u.locked_until > now() then
    raise exception 'BLOQUEADO';
  end if;
  if not u.active or u.password_hash <> privado.crypt(coalesce(p_password, ''), u.password_hash) then
    update comun.usuarios
       set failed_attempts = failed_attempts + 1,
           locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' end
     where id = u.id;
    return jsonb_build_object('error', 'CREDENCIALES');
  end if;
  update comun.usuarios set failed_attempts = 0, locked_until = null where id = u.id;
  return privado.abrir_sesion_gymbro(u.id);
end $$;

-- Quién soy (al abrir la app con la sesión guardada). Alarga la sesión si le queda poco.
create or replace function public.yo_gymbro(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; u comun.usuarios;
begin
  s := privado.socio_de_token_gymbro(p_token);
  update comun.sesiones set expires_at = now() + interval '60 days'
   where token_hash = privado.digest(p_token, 'sha256') and expires_at < now() + interval '30 days';
  select * into u from comun.usuarios where id = s.usuario_id;
  return jsonb_build_object('id', u.id, 'nombre', u.name, 'email', u.email, 'rol', s.rol,
                            'cambiar_password', u.must_change_password,
                            'negocio', privado.negocio_json_gymbro(s.negocio_id));
end $$;

-- Salir: cierra solo esta sesión.
create or replace function public.salir_gymbro(p_token text)
returns void
language sql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
  delete from comun.sesiones
   where token_hash = privado.digest(coalesce(p_token, ''), 'sha256')
     and usuario_id in (select usuario_id from gymbro.socios_gymbro);
$$;

-- Cambiar la contraseña sabiendo la actual. Cierra las demás sesiones.
create or replace function public.cambiar_password_gymbro(p_token text, p_actual text, p_nueva text)
returns void
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_hash text;
begin
  s := privado.socio_de_token_gymbro(p_token);
  select password_hash into v_hash from comun.usuarios where id = s.usuario_id;
  if v_hash <> privado.crypt(coalesce(p_actual, ''), v_hash) then
    raise exception 'CREDENCIALES';
  end if;
  if length(coalesce(p_nueva, '')) < 8 or length(p_nueva) > 72 then
    raise exception 'PASSWORD_CORTA';
  end if;
  update comun.usuarios set password_hash = privado.crypt(p_nueva, privado.gen_salt('bf', 10)),
                            must_change_password = false
   where id = s.usuario_id;
  delete from comun.sesiones
   where usuario_id = s.usuario_id and token_hash <> privado.digest(p_token, 'sha256');
end $$;

-- Todo lo guardado de la persona: progreso y ejercicios propios.
create or replace function public.mis_datos_gymbro(p_token text)
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_de_token_gymbro(p_token);
  return jsonb_build_object(
    'progreso', (select coalesce(jsonb_agg(jsonb_build_object(
                   'work_key', p.work_key, 'peso', p.peso, 'series', p.series, 'reps', p.reps,
                   'checked', p.checked, 'ejercicio_elegido', p.ejercicio_elegido,
                   'updated_at', p.updated_at) order by p.work_key), '[]'::jsonb)
                   from gymbro.progreso_gymbro p where p.usuario_id = s.usuario_id),
    'personalizados', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', e.id, 'sub_id', e.sub_id, 'nombre', e.nombre, 'video_url', e.video_url)
                   order by e.created_at), '[]'::jsonb)
                   from gymbro.ejercicios_personalizados_gymbro e where e.usuario_id = s.usuario_id));
end $$;

-- Guardar filas de progreso. Cada fila solo cambia los campos que trae
-- (igual que el «upsert» que usaba War300).
create or replace function public.guardar_progreso_gymbro(p_token text, p_filas jsonb)
returns int
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; f jsonb; v_n int := 0;
begin
  s := privado.socio_de_token_gymbro(p_token);
  if jsonb_typeof(p_filas) = 'object' then
    p_filas := jsonb_build_array(p_filas);
  end if;
  if jsonb_typeof(p_filas) is distinct from 'array' or jsonb_array_length(p_filas) > 1000 then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  for f in select * from jsonb_array_elements(p_filas) loop
    if jsonb_typeof(f) <> 'object' or coalesce(f->>'work_key', '') = '' then
      raise exception 'DATOS_NO_VALIDOS';
    end if;
    insert into gymbro.progreso_gymbro as p
           (negocio_id, usuario_id, work_key, peso, series, reps, checked, ejercicio_elegido)
    values (s.negocio_id, s.usuario_id, f->>'work_key', (f->>'peso')::numeric, f->>'series',
            f->>'reps', coalesce((f->>'checked')::boolean, false), f->>'ejercicio_elegido')
    on conflict (usuario_id, work_key) do update set
      peso              = case when f ? 'peso'              then excluded.peso              else p.peso end,
      series            = case when f ? 'series'            then excluded.series            else p.series end,
      reps              = case when f ? 'reps'              then excluded.reps              else p.reps end,
      checked           = case when f ? 'checked'           then excluded.checked           else p.checked end,
      ejercicio_elegido = case when f ? 'ejercicio_elegido' then excluded.ejercicio_elegido else p.ejercicio_elegido end,
      updated_at        = now();
    v_n := v_n + 1;
  end loop;
  return v_n;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    raise exception 'DATOS_NO_VALIDOS';
end $$;

-- Entrenos terminados de la persona (los más recientes, como mucho 1000).
create or replace function public.mis_entrenos_gymbro(p_token text, p_desde date default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_de_token_gymbro(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', x.id, 'fecha', x.fecha, 'resumen', x.resumen, 'dia', x.dia,
            'tipo', x.tipo, 'created_at', x.created_at) order by x.fecha, x.created_at), '[]'::jsonb)
            from (select * from gymbro.entrenos_gymbro e
                   where e.usuario_id = s.usuario_id and (p_desde is null or e.fecha >= p_desde)
                   order by e.fecha desc, e.created_at desc limit 1000) x);
end $$;

-- Guardar un entreno terminado.
create or replace function public.guardar_entreno_gymbro(p_token text, p_fecha date, p_resumen jsonb,
                                                         p_dia int default null, p_tipo text default 'gym')
returns uuid
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_id uuid;
begin
  s := privado.socio_de_token_gymbro(p_token);
  if p_resumen is null or p_fecha is null or p_fecha > current_date + 1 or p_fecha < date '2020-01-01' then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  if (select count(*) from gymbro.entrenos_gymbro
       where usuario_id = s.usuario_id and created_at > now() - interval '1 day') >= 50 then
    raise exception 'DEMASIADOS_INTENTOS';
  end if;
  insert into gymbro.entrenos_gymbro (negocio_id, usuario_id, fecha, resumen, dia, tipo)
  values (s.negocio_id, s.usuario_id, p_fecha, p_resumen, p_dia, coalesce(p_tipo, 'gym'))
  returning id into v_id;
  return v_id;
exception
  when check_violation then
    raise exception 'DATOS_NO_VALIDOS';
end $$;

-- Añadir un ejercicio propio.
create or replace function public.guardar_personalizado_gymbro(p_token text, p_sub_id text, p_nombre text,
                                                              p_video_url text default null)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_id uuid;
begin
  s := privado.socio_de_token_gymbro(p_token);
  if (select count(*) from gymbro.ejercicios_personalizados_gymbro where usuario_id = s.usuario_id) >= 300 then
    raise exception 'DEMASIADOS_EJERCICIOS';
  end if;
  insert into gymbro.ejercicios_personalizados_gymbro (negocio_id, usuario_id, sub_id, nombre, video_url)
  values (s.negocio_id, s.usuario_id, btrim(coalesce(p_sub_id, '')), btrim(coalesce(p_nombre, '')),
          nullif(btrim(coalesce(p_video_url, '')), ''))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'sub_id', p_sub_id, 'nombre', btrim(p_nombre),
                            'video_url', nullif(btrim(coalesce(p_video_url, '')), ''));
exception
  when check_violation then
    raise exception 'DATOS_NO_VALIDOS';
end $$;

-- Borrar mi cuenta (derecho de supresión). Pide la contraseña.
-- Borra sus datos de Gymbro y deja la cuenta anónima y apagada
-- (la fila de comun.usuarios se queda para no romper referencias).
create or replace function public.borrar_mi_cuenta_gymbro(p_token text, p_password text)
returns void
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_hash text;
begin
  s := privado.socio_de_token_gymbro(p_token);
  select password_hash into v_hash from comun.usuarios where id = s.usuario_id;
  if v_hash <> privado.crypt(coalesce(p_password, ''), v_hash) then
    raise exception 'CREDENCIALES';
  end if;
  delete from gymbro.progreso_gymbro                  where usuario_id = s.usuario_id;
  delete from gymbro.entrenos_gymbro                  where usuario_id = s.usuario_id;
  delete from gymbro.ejercicios_personalizados_gymbro where usuario_id = s.usuario_id;
  delete from comun.sesiones       where usuario_id = s.usuario_id;
  delete from comun.recuperaciones where usuario_id = s.usuario_id;
  update comun.usuarios
     set email = 'borrada-' || id || '@cuenta-borrada.invalid', name = 'Cuenta borrada', active = false,
         password_hash = privado.crypt(encode(privado.gen_random_bytes(24), 'hex'), privado.gen_salt('bf', 10))
   where id = s.usuario_id;
end $$;

-- ---------------------------------------------------------------------
-- Permisos: la web (anon) solo puede llamar a estas funciones.
-- ---------------------------------------------------------------------
revoke all on function privado.negocio_gymbro(text)              from public, anon, authenticated;
revoke all on function privado.socio_de_token_gymbro(text)       from public, anon, authenticated;
revoke all on function privado.negocio_json_gymbro(int)          from public, anon, authenticated;
revoke all on function privado.abrir_sesion_gymbro(int)          from public, anon, authenticated;

revoke all on function public.negocio_gymbro(text)                                    from public;
revoke all on function public.registrar_gymbro(text, text, text, text)                from public;
revoke all on function public.entrar_gymbro(text, text, text)                         from public;
revoke all on function public.yo_gymbro(text)                                         from public;
revoke all on function public.salir_gymbro(text)                                      from public;
revoke all on function public.cambiar_password_gymbro(text, text, text)               from public;
revoke all on function public.mis_datos_gymbro(text)                                  from public;
revoke all on function public.guardar_progreso_gymbro(text, jsonb)                    from public;
revoke all on function public.mis_entrenos_gymbro(text, date)                         from public;
revoke all on function public.guardar_entreno_gymbro(text, date, jsonb, int, text)    from public;
revoke all on function public.guardar_personalizado_gymbro(text, text, text, text)    from public;
revoke all on function public.borrar_mi_cuenta_gymbro(text, text)                     from public;

grant execute on function public.negocio_gymbro(text)                                 to anon, authenticated;
grant execute on function public.registrar_gymbro(text, text, text, text)             to anon, authenticated;
grant execute on function public.entrar_gymbro(text, text, text)                      to anon, authenticated;
grant execute on function public.yo_gymbro(text)                                      to anon, authenticated;
grant execute on function public.salir_gymbro(text)                                   to anon, authenticated;
grant execute on function public.cambiar_password_gymbro(text, text, text)            to anon, authenticated;
grant execute on function public.mis_datos_gymbro(text)                               to anon, authenticated;
grant execute on function public.guardar_progreso_gymbro(text, jsonb)                 to anon, authenticated;
grant execute on function public.mis_entrenos_gymbro(text, date)                      to anon, authenticated;
grant execute on function public.guardar_entreno_gymbro(text, date, jsonb, int, text) to anon, authenticated;
grant execute on function public.guardar_personalizado_gymbro(text, text, text, text) to anon, authenticated;
grant execute on function public.borrar_mi_cuenta_gymbro(text, text)                  to anon, authenticated;

commit;
