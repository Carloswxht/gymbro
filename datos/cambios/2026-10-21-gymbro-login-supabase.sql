-- =====================================================================
-- Gymbro · login de Supabase (21 oct 2026, v107)
-- =====================================================================
-- Decisión de Carlos (21 oct): todas las cuentas entran con el login de
-- Supabase (guía: AutonomIA-Lab docs/login-supabase-productos.md). La parte
-- común ya está en la base (comun.usuarios.auth_id, copias con auth.users,
-- privado.es_plataforma, privado.limpiar_correo): aquí NO se toca comun.
--
-- Qué añade (sin cambiar ni borrar nada de lo que hay):
--   · Ayudantes que reconocen a la persona por auth.uid() (su cuenta de
--     Supabase) en vez de por el token propio: privado.socio_auth_gymbro,
--     privado.admin_auth_gymbro, privado.exigir_plataforma_gymbro.
--   · Las mismas funciones de siempre SIN p_token (mismo nombre, otra
--     firma): idénticas a las probadas salvo cómo reconocen a quien llama.
--     Solo para «authenticated». Las de token se quedan hasta que la web
--     nueva funcione; después se les quita el permiso (sin DROP).
--   · yo_gymbro(), plataforma_yo_gymbro() y crear_cuenta_gymbro() (el
--     registro libre: crea la cuenta y la web entra con Supabase).
-- Recuperar la contraseña y la invitación de bienvenida siguen con los
-- correos propios de Gymbro (la plantilla de Supabase lleva a la web de
-- autonomIA Lab): al elegir la contraseña, la copia pasa sola a Supabase.
-- Se puede volver a ejecutar.
-- =====================================================================

begin;

-- Socio a partir de su cuenta de Supabase: cuenta activa, de un gimnasio
-- activo y dada de alta en socios_gymbro (una cuenta de otro producto no vale).
create or replace function privado.socio_auth_gymbro()
returns gymbro.socios_gymbro
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  select so.* into s
    from comun.usuarios us
    join gymbro.socios_gymbro so on so.usuario_id = us.id and so.negocio_id = us.negocio_id
    join comun.negocios n on n.id = us.negocio_id
   where us.auth_id = auth.uid() and us.active and n.activo and n.tipo = 'gymbro';
  if not found then
    raise exception 'SESION_CADUCADA';
  end if;
  return s;
end $$;

create or replace function privado.admin_auth_gymbro()
returns gymbro.socios_gymbro
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_auth_gymbro();
  if s.rol <> 'admin' then
    raise exception 'SIN_PERMISO';
  end if;
  return s;
end $$;

-- Cuenta de plataforma de Carlos (la común: privado.es_plataforma).
create or replace function privado.exigir_plataforma_gymbro()
returns void
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
begin
  if not privado.es_plataforma() then
    raise exception 'SESION_CADUCADA';
  end if;
end $$;

-- Quién soy (la app y el panel, al abrir).
create or replace function public.yo_gymbro()
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; u comun.usuarios;
begin
  s := privado.socio_auth_gymbro();
  select * into u from comun.usuarios where id = s.usuario_id;
  return jsonb_build_object('id', u.id, 'nombre', u.name, 'email', u.email, 'rol', s.rol,
                            'cambiar_password', u.must_change_password,
                            'negocio', privado.negocio_json_gymbro(s.negocio_id));
end $$;

-- Quién soy en /plataforma/.
create or replace function public.plataforma_yo_gymbro()
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
begin
  perform privado.exigir_plataforma_gymbro();
  return (select jsonb_build_object('nombre', u.name, 'email', u.email)
            from comun.usuarios u where u.auth_id = auth.uid());
end $$;

-- Registro libre: crea la cuenta (su cuenta de Supabase nace sola, con la
-- misma contraseña) y la web entra con Supabase. Mismas reglas que
-- registrar_gymbro, sin abrir sesión propia.
create or replace function public.crear_cuenta_gymbro(p_slug text, p_email text, p_password text, p_nombre text default null)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; v_email text := privado.limpiar_correo(p_email); v_nombre text; v_id int;
begin
  n := privado.negocio_gymbro(p_slug);
  if not coalesce((select registro_abierto from gymbro.ajustes_gymbro where negocio_id = n.id), false) then
    raise exception 'REGISTRO_CERRADO';
  end if;
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
  begin
    insert into comun.usuarios (negocio_id, email, name, password_hash, must_change_password)
    values (n.id, v_email, v_nombre, privado.crypt(p_password, privado.gen_salt('bf', 10)), false)
    returning id into v_id;
  exception when raise_exception then
    -- CORREO_EN_USO del disparador común: ya es de un miembro de la web.
    if sqlerrm = 'CORREO_EN_USO' then raise exception 'EMAIL_EN_USO'; end if;
    raise;
  end;
  insert into gymbro.socios_gymbro (usuario_id, negocio_id, rol) values (v_id, n.id, 'socio');
  return jsonb_build_object('email', v_email);
end $$;

-- ---------------------------------------------------------------------
-- Las funciones de siempre, sin p_token (copiadas de las probadas; solo
-- cambia cómo reconocen a quien llama).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.aceptar_legal_gymbro(p_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_auth_gymbro();
  if p_version is distinct from privado.version_legal_gymbro() then
    raise exception 'VERSION_NO_VALIDA';
  end if;
  insert into gymbro.consentimientos_gymbro (usuario_id, negocio_id, version)
  values (s.usuario_id, s.negocio_id, p_version)
  on conflict (usuario_id, version) do nothing;
  return public.legal_estado_gymbro();
end $function$;

CREATE OR REPLACE FUNCTION public.borrar_mi_cuenta_gymbro(p_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v_hash text;
begin
  s := privado.socio_auth_gymbro();
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
end $function$;

CREATE OR REPLACE FUNCTION public.guardar_entreno_gymbro(p_fecha date, p_resumen jsonb, p_dia integer DEFAULT NULL::integer, p_tipo text DEFAULT 'gym'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v_id uuid;
begin
  s := privado.socio_auth_gymbro();
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
end $function$;

CREATE OR REPLACE FUNCTION public.guardar_personalizado_gymbro(p_sub_id text, p_nombre text, p_video_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v_id uuid;
begin
  s := privado.socio_auth_gymbro();
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
end $function$;

CREATE OR REPLACE FUNCTION public.guardar_progreso_gymbro(p_filas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; f jsonb; v_n int := 0;
begin
  s := privado.socio_auth_gymbro();
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
end $function$;

CREATE OR REPLACE FUNCTION public.legal_estado_gymbro()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v text := privado.version_legal_gymbro(); a timestamptz;
begin
  s := privado.socio_auth_gymbro();
  select aceptado_at into a from gymbro.consentimientos_gymbro where usuario_id = s.usuario_id and version = v;
  return jsonb_build_object('version', v, 'aceptada', a is not null, 'aceptada_at', a);
end $function$;

CREATE OR REPLACE FUNCTION public.mis_datos_gymbro()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_auth_gymbro();
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
end $function$;

CREATE OR REPLACE FUNCTION public.mis_entrenos_gymbro(p_desde date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_auth_gymbro();
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', x.id, 'fecha', x.fecha, 'resumen', x.resumen, 'dia', x.dia,
            'tipo', x.tipo, 'created_at', x.created_at) order by x.fecha, x.created_at), '[]'::jsonb)
            from (select * from gymbro.entrenos_gymbro e
                   where e.usuario_id = s.usuario_id and (p_desde is null or e.fecha >= p_desde)
                   order by e.fecha desc, e.created_at desc limit 1000) x);
end $function$;

CREATE OR REPLACE FUNCTION public.panel_alta_socio_gymbro(p_email text, p_nombre text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v_email text; v_nombre text; v_id int;
begin
  s := privado.admin_auth_gymbro();
  v_email := lower(btrim(coalesce(p_email, '')));
  v_nombre := left(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g')), 60);
  if v_nombre = '' then
    raise exception 'FALTAN_DATOS';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' or length(v_email) > 254 then
    raise exception 'EMAIL_NO_VALIDO';
  end if;
  -- Freno: como mucho 50 altas al día en cada gimnasio.
  if (select count(*) from gymbro.socios_gymbro
       where negocio_id = s.negocio_id and created_at > now() - interval '1 day') >= 50 then
    raise exception 'DEMASIADOS_INTENTOS';
  end if;
  if exists (select 1 from comun.usuarios where lower(email) = v_email) then
    raise exception 'EMAIL_EN_USO';
  end if;
  insert into comun.usuarios (negocio_id, email, name, password_hash, must_change_password)
  values (s.negocio_id, v_email, v_nombre,
          privado.crypt(encode(privado.gen_random_bytes(24), 'hex'), privado.gen_salt('bf', 10)), true)
  returning id into v_id;
  insert into gymbro.socios_gymbro (usuario_id, negocio_id, rol) values (v_id, s.negocio_id, 'socio');
  return jsonb_build_object('id', v_id, 'email', v_email);
end $function$;

CREATE OR REPLACE FUNCTION public.panel_estado_socio_gymbro(p_usuario integer, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; o gymbro.socios_gymbro;
begin
  s := privado.admin_auth_gymbro();
  o := privado.socio_del_negocio_gymbro(s.negocio_id, p_usuario);
  if p_activo is null then
    raise exception 'FALTAN_DATOS';
  end if;
  if o.usuario_id = s.usuario_id and not p_activo then
    raise exception 'NO_A_TI_MISMO';
  end if;
  update comun.usuarios set active = p_activo where id = o.usuario_id;
  if not p_activo then
    update comun.sesiones set expires_at = now() where usuario_id = o.usuario_id and expires_at > now();
  end if;
  if not exists (select 1 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                  where so.negocio_id = s.negocio_id and so.rol = 'admin' and u.active) then
    raise exception 'ULTIMO_ADMIN';
  end if;
  return jsonb_build_object('id', o.usuario_id, 'activo', p_activo);
end $function$;

CREATE OR REPLACE FUNCTION public.panel_gymbro()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; v_zona text; v_hoy date;
begin
  s := privado.admin_auth_gymbro();
  select coalesce(zona_horaria, 'Europe/Madrid') into v_zona from comun.negocios where id = s.negocio_id;
  v_hoy := (now() at time zone v_zona)::date;
  return jsonb_build_object(
    'yo', s.usuario_id,
    'negocio', privado.negocio_json_gymbro(s.negocio_id),
    'socios', (select coalesce(jsonb_agg(x order by x->>'activo' desc, lower(x->>'nombre')), '[]'::jsonb) from (
      select jsonb_build_object(
        'id', u.id, 'nombre', u.name, 'email', u.email, 'rol', so.rol, 'activo', u.active,
        'pendiente', u.must_change_password, 'alta', so.created_at,
        'ultimo_entreno', (select max(e.fecha) from gymbro.entrenos_gymbro e where e.usuario_id = u.id),
        'entrenos_mes', (select count(*) from gymbro.entrenos_gymbro e
                          where e.usuario_id = u.id and e.fecha >= date_trunc('month', v_hoy)::date),
        'entrenos_semana', (select count(*) from gymbro.entrenos_gymbro e
                          where e.usuario_id = u.id and e.fecha >= date_trunc('week', v_hoy)::date)) as x
        from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
       where so.negocio_id = s.negocio_id and u.email not like '%@cuenta-borrada.invalid') t));
end $function$;

CREATE OR REPLACE FUNCTION public.panel_registro_gymbro(p_abierto boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro;
begin
  s := privado.admin_auth_gymbro();
  if p_abierto is null then
    raise exception 'FALTAN_DATOS';
  end if;
  insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) values (s.negocio_id, p_abierto)
  on conflict (negocio_id) do update set registro_abierto = excluded.registro_abierto, updated_at = now();
  return jsonb_build_object('registro_abierto', p_abierto);
end $function$;

CREATE OR REPLACE FUNCTION public.panel_rol_socio_gymbro(p_usuario integer, p_rol text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare s gymbro.socios_gymbro; o gymbro.socios_gymbro;
begin
  s := privado.admin_auth_gymbro();
  o := privado.socio_del_negocio_gymbro(s.negocio_id, p_usuario);
  if p_rol is null or p_rol not in ('socio', 'admin') then
    raise exception 'ROL_NO_VALIDO';
  end if;
  update gymbro.socios_gymbro set rol = p_rol where usuario_id = o.usuario_id;
  if not exists (select 1 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                  where so.negocio_id = s.negocio_id and so.rol = 'admin' and u.active) then
    raise exception 'ULTIMO_ADMIN';
  end if;
  return jsonb_build_object('id', o.usuario_id, 'rol', p_rol);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_alta_gimnasio_gymbro(p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare
  v_nombre text := btrim(coalesce(p_datos->>'nombre', ''));
  v_slug   text := lower(btrim(coalesce(p_datos->>'slug', '')));
  v_email  text := rtrim(lower(btrim(coalesce(p_datos->>'email', ''))), '.');
  v_dueno  text := btrim(coalesce(p_datos->>'dueno', ''));
  v_id int; v_uid int;
begin
  perform privado.exigir_plataforma_gymbro();
  if v_nombre = '' or length(v_nombre) > 60 then
    raise exception 'FALTAN_DATOS';
  end if;
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,39}$'
     or v_slug in ('autonomialab', 'plataforma', 'panel', 'admin', 'www', 'api', 'gymbro', 'multibar') then
    raise exception 'SLUG_NO_VALIDO';
  end if;
  if exists (select 1 from comun.negocios where slug = v_slug) then
    raise exception 'SLUG_EN_USO';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' or length(v_email) > 254 then
    raise exception 'EMAIL_NO_VALIDO';
  end if;
  if exists (select 1 from comun.usuarios where lower(email) = v_email) then
    raise exception 'EMAIL_EN_USO';
  end if;
  if v_dueno = '' then
    v_dueno := 'Administrador';
  end if;
  v_dueno := left(v_dueno, 60);

  insert into comun.negocios (slug, nombre, tipo) values (v_slug, v_nombre, 'gymbro') returning id into v_id;
  insert into comun.productos_contratados (negocio_id, producto) values (v_id, 'gymbro');
  insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto)
  values (v_id, coalesce((p_datos->>'registro_abierto')::boolean, false));
  insert into comun.usuarios (negocio_id, email, name, password_hash, must_change_password)
  values (v_id, v_email, v_dueno,
          privado.crypt(encode(privado.gen_random_bytes(24), 'hex'), privado.gen_salt('bf', 10)), true)
  returning id into v_uid;
  insert into gymbro.socios_gymbro (usuario_id, negocio_id, rol) values (v_uid, v_id, 'admin');
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'email', v_email);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_aspecto_gymbro(p_id integer, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare n comun.negocios; v_nombre text := btrim(coalesce(p_datos->>'nombre', '')); v_aspecto jsonb;
begin
  perform privado.exigir_plataforma_gymbro();
  n := privado.gimnasio_gymbro(p_id);
  if v_nombre = '' or length(v_nombre) > 60 then
    raise exception 'FALTAN_DATOS';
  end if;
  v_aspecto := privado.aspecto_limpio_gymbro(p_datos);
  update comun.negocios set nombre = v_nombre where id = n.id;
  insert into gymbro.ajustes_gymbro (negocio_id, aspecto) values (n.id, v_aspecto)
  on conflict (negocio_id) do update set aspecto = excluded.aspecto, updated_at = now();
  return privado.negocio_json_gymbro(n.id);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_estado_gimnasio_gymbro(p_id integer, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare n comun.negocios;
begin
  perform privado.exigir_plataforma_gymbro();
  if p_activo is null then
    raise exception 'FALTAN_DATOS';
  end if;
  n := privado.gimnasio_gymbro(p_id);
  update comun.negocios set activo = p_activo, baja_at = case when p_activo then null else now() end
   where id = n.id;
  update comun.productos_contratados set activo = p_activo where negocio_id = n.id and producto = 'gymbro';
  return jsonb_build_object('id', n.id, 'activo', p_activo);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_gimnasio_gymbro(p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare n comun.negocios;
begin
  perform privado.exigir_plataforma_gymbro();
  n := privado.gimnasio_gymbro(p_id);
  return privado.negocio_json_gymbro(n.id) || jsonb_build_object(
    'id', n.id, 'activo', n.activo, 'alta', n.created_at, 'baja', n.baja_at,
    'logo_gymbro', (select logo from gymbro.ajustes_gymbro where negocio_id = n.id),
    'legal', privado.datos_legales_gymbro(n.id),
    'cifras', privado.cifras_gimnasio_gymbro(n.id),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', u.id, 'nombre', u.name, 'email', u.email, 'activo', u.active,
                 'pendiente', u.must_change_password) order by u.created_at), '[]'::jsonb)
                 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                where so.negocio_id = n.id and so.rol = 'admin'
                  and u.email not like '%@cuenta-borrada.invalid'));
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_gimnasios_gymbro()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
begin
  perform privado.exigir_plataforma_gymbro();
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', n.id, 'slug', n.slug, 'nombre', n.nombre, 'activo', n.activo,
            'alta', n.created_at, 'baja', n.baja_at,
            'registro_abierto', coalesce(a.registro_abierto, false),
            'cifras', privado.cifras_gimnasio_gymbro(n.id))
            order by n.activo desc, lower(n.nombre)), '[]'::jsonb)
            from comun.negocios n left join gymbro.ajustes_gymbro a on a.negocio_id = n.id
           where n.tipo = 'gymbro');
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_legal_gymbro(p_id integer, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare
  n comun.negocios;
  v_titular text := nullif(btrim(coalesce(p_datos->>'titular', '')), '');
  v_nif     text := nullif(upper(regexp_replace(coalesce(p_datos->>'nif', ''), '[\s.-]', '', 'g')), '');
  v_dom     text := nullif(btrim(coalesce(p_datos->>'domicilio', '')), '');
  v_correo  text := nullif(rtrim(lower(btrim(coalesce(p_datos->>'correo', ''))), '.'), '');
  v_tel     text := nullif(btrim(coalesce(p_datos->>'telefono', '')), '');
begin
  perform privado.exigir_plataforma_gymbro();
  n := privado.gimnasio_gymbro(p_id);
  if length(v_titular) > 120 or length(v_dom) > 200 or length(v_tel) > 30
     or (v_nif is not null and v_nif !~ '^[A-Z0-9]{8,12}$') then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  if v_correo is not null and (v_correo !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' or length(v_correo) > 254) then
    raise exception 'EMAIL_NO_VALIDO';
  end if;
  update comun.negocios
     set titular = v_titular, nif = v_nif, domicilio_fiscal = v_dom, correo_legal = v_correo, telefono_legal = v_tel
   where id = n.id;
  return privado.datos_legales_gymbro(n.id);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_logo_gymbro(p_id integer, p_logo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare n comun.negocios;
begin
  perform privado.exigir_plataforma_gymbro();
  n := privado.gimnasio_gymbro(p_id);
  if p_logo is not null and not (
       p_logo ~ '^/icons/[a-z0-9-]{1,40}[.]png$'
       or (p_logo ~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' and length(p_logo) <= 400000)) then
    raise exception 'LOGO_NO_VALIDO';
  end if;
  insert into gymbro.ajustes_gymbro (negocio_id, logo) values (n.id, p_logo)
  on conflict (negocio_id) do update set logo = excluded.logo, updated_at = now();
  return jsonb_build_object('id', n.id,
    'logo_v', case when p_logo is not null then left(md5(p_logo), 12) end);
end $function$;

CREATE OR REPLACE FUNCTION public.plataforma_registro_gymbro(p_id integer, p_abierto boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'comun', 'gymbro', 'privado', 'pg_temp'
AS $function$
declare n comun.negocios;
begin
  perform privado.exigir_plataforma_gymbro();
  if p_abierto is null then
    raise exception 'FALTAN_DATOS';
  end if;
  n := privado.gimnasio_gymbro(p_id);
  insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) values (n.id, p_abierto)
  on conflict (negocio_id) do update set registro_abierto = excluded.registro_abierto, updated_at = now();
  return jsonb_build_object('id', n.id, 'registro_abierto', p_abierto);
end $function$;

-- Permisos: la web solo con sesión de Supabase (authenticated), nunca anon.
revoke all on function privado.socio_auth_gymbro()       from public, anon, authenticated;
revoke all on function privado.admin_auth_gymbro()       from public, anon, authenticated;
revoke all on function privado.exigir_plataforma_gymbro() from public, anon, authenticated;
revoke all on function public.yo_gymbro() from public, anon;
grant execute on function public.yo_gymbro() to authenticated;
revoke all on function public.plataforma_yo_gymbro() from public, anon;
grant execute on function public.plataforma_yo_gymbro() to authenticated;
revoke all on function public.aceptar_legal_gymbro(text) from public, anon;
grant execute on function public.aceptar_legal_gymbro(text) to authenticated;
revoke all on function public.borrar_mi_cuenta_gymbro(text) from public, anon;
grant execute on function public.borrar_mi_cuenta_gymbro(text) to authenticated;
revoke all on function public.guardar_entreno_gymbro(date,jsonb,integer,text) from public, anon;
grant execute on function public.guardar_entreno_gymbro(date,jsonb,integer,text) to authenticated;
revoke all on function public.guardar_personalizado_gymbro(text,text,text) from public, anon;
grant execute on function public.guardar_personalizado_gymbro(text,text,text) to authenticated;
revoke all on function public.guardar_progreso_gymbro(jsonb) from public, anon;
grant execute on function public.guardar_progreso_gymbro(jsonb) to authenticated;
revoke all on function public.legal_estado_gymbro() from public, anon;
grant execute on function public.legal_estado_gymbro() to authenticated;
revoke all on function public.mis_datos_gymbro() from public, anon;
grant execute on function public.mis_datos_gymbro() to authenticated;
revoke all on function public.mis_entrenos_gymbro(date) from public, anon;
grant execute on function public.mis_entrenos_gymbro(date) to authenticated;
revoke all on function public.panel_alta_socio_gymbro(text,text) from public, anon;
grant execute on function public.panel_alta_socio_gymbro(text,text) to authenticated;
revoke all on function public.panel_estado_socio_gymbro(integer,boolean) from public, anon;
grant execute on function public.panel_estado_socio_gymbro(integer,boolean) to authenticated;
revoke all on function public.panel_gymbro() from public, anon;
grant execute on function public.panel_gymbro() to authenticated;
revoke all on function public.panel_registro_gymbro(boolean) from public, anon;
grant execute on function public.panel_registro_gymbro(boolean) to authenticated;
revoke all on function public.panel_rol_socio_gymbro(integer,text) from public, anon;
grant execute on function public.panel_rol_socio_gymbro(integer,text) to authenticated;
revoke all on function public.plataforma_alta_gimnasio_gymbro(jsonb) from public, anon;
grant execute on function public.plataforma_alta_gimnasio_gymbro(jsonb) to authenticated;
revoke all on function public.plataforma_aspecto_gymbro(integer,jsonb) from public, anon;
grant execute on function public.plataforma_aspecto_gymbro(integer,jsonb) to authenticated;
revoke all on function public.plataforma_estado_gimnasio_gymbro(integer,boolean) from public, anon;
grant execute on function public.plataforma_estado_gimnasio_gymbro(integer,boolean) to authenticated;
revoke all on function public.plataforma_gimnasio_gymbro(integer) from public, anon;
grant execute on function public.plataforma_gimnasio_gymbro(integer) to authenticated;
revoke all on function public.plataforma_gimnasios_gymbro() from public, anon;
grant execute on function public.plataforma_gimnasios_gymbro() to authenticated;
revoke all on function public.plataforma_legal_gymbro(integer,jsonb) from public, anon;
grant execute on function public.plataforma_legal_gymbro(integer,jsonb) to authenticated;
revoke all on function public.plataforma_logo_gymbro(integer,text) from public, anon;
grant execute on function public.plataforma_logo_gymbro(integer,text) to authenticated;
revoke all on function public.plataforma_registro_gymbro(integer,boolean) from public, anon;
grant execute on function public.plataforma_registro_gymbro(integer,boolean) to authenticated;
revoke all on function public.crear_cuenta_gymbro(text, text, text, text) from public;
grant execute on function public.crear_cuenta_gymbro(text, text, text, text) to anon, authenticated;

commit;
