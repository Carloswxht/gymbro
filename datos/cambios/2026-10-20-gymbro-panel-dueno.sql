-- =====================================================================
-- Gymbro · panel del dueño de cada gimnasio (20 oct 2026)
-- =====================================================================
-- Solo AÑADE funciones (no cambia tablas ni nada de MultiBar). Las usa
-- `/panel/` con la sesión de una cuenta con rol `admin` de su gimnasio.
-- Se puede volver a ejecutar.
-- =====================================================================

begin;

-- Admin a partir de su sesión (si no es admin: SIN_PERMISO).
create or replace function privado.admin_de_token_gymbro(p_token text)
returns gymbro.socios_gymbro
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_de_token_gymbro(p_token);
  if s.rol <> 'admin' then
    raise exception 'SIN_PERMISO';
  end if;
  return s;
end $$;

-- Socio del mismo gimnasio que el admin (si no: USUARIO_NO_VALIDO).
create or replace function privado.socio_del_negocio_gymbro(p_negocio int, p_usuario int)
returns gymbro.socios_gymbro
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  select so.* into s from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
   where so.usuario_id = p_usuario and so.negocio_id = p_negocio
     and u.email not like '%@cuenta-borrada.invalid';
  if not found then
    raise exception 'USUARIO_NO_VALIDO';
  end if;
  return s;
end $$;

-- Todo lo que pinta el panel: el gimnasio y sus socios.
create or replace function public.panel_gymbro(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_zona text; v_hoy date;
begin
  s := privado.admin_de_token_gymbro(p_token);
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
end $$;

-- Dar de alta a un socio por correo. Queda «pendiente» hasta que elige su
-- contraseña con el correo de bienvenida (lo manda la Edge Function).
create or replace function public.panel_alta_socio_gymbro(p_token text, p_email text, p_nombre text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v_email text; v_nombre text; v_id int;
begin
  s := privado.admin_de_token_gymbro(p_token);
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
end $$;

-- Dar de baja o reactivar (sin borrar nada). Al dar de baja se cierran sus sesiones.
create or replace function public.panel_estado_socio_gymbro(p_token text, p_usuario int, p_activo boolean)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; o gymbro.socios_gymbro;
begin
  s := privado.admin_de_token_gymbro(p_token);
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
end $$;

-- Cambiar el rol (socio / admin). Siempre queda al menos un admin activo.
create or replace function public.panel_rol_socio_gymbro(p_token text, p_usuario int, p_rol text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; o gymbro.socios_gymbro;
begin
  s := privado.admin_de_token_gymbro(p_token);
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
end $$;

-- Abrir o cerrar el registro libre del gimnasio.
create or replace function public.panel_registro_gymbro(p_token text, p_abierto boolean)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.admin_de_token_gymbro(p_token);
  if p_abierto is null then
    raise exception 'FALTAN_DATOS';
  end if;
  insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) values (s.negocio_id, p_abierto)
  on conflict (negocio_id) do update set registro_abierto = excluded.registro_abierto, updated_at = now();
  return jsonb_build_object('registro_abierto', p_abierto);
end $$;

-- Enlace de bienvenida (solo el servidor): solo para socios que aún no han
-- elegido contraseña. Vale 3 días.
create or replace function public.bienvenida_crear_gymbro(p_email text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare u comun.usuarios; n comun.negocios; v_token text;
begin
  select us.* into u
    from comun.usuarios us join gymbro.socios_gymbro so on so.usuario_id = us.id
   where lower(us.email) = lower(btrim(coalesce(p_email, ''))) and us.active and us.must_change_password;
  if not found then
    return null;
  end if;
  select * into n from comun.negocios where id = u.negocio_id and tipo = 'gymbro' and activo;
  if not found then
    return null;
  end if;
  v_token := privado.crear_enlace(u.id, 3 * 24 * 60);
  if v_token is null then
    return null;
  end if;
  return jsonb_build_object('token', v_token, 'email', u.email, 'nombre', u.name,
                            'negocio_nombre', n.nombre, 'negocio_slug', n.slug, 'bienvenida', true);
end $$;

revoke all on function privado.admin_de_token_gymbro(text)              from public, anon, authenticated;
revoke all on function privado.socio_del_negocio_gymbro(int, int)       from public, anon, authenticated;
revoke all on function public.panel_gymbro(text)                        from public;
revoke all on function public.panel_alta_socio_gymbro(text, text, text) from public;
revoke all on function public.panel_estado_socio_gymbro(text, int, boolean) from public;
revoke all on function public.panel_rol_socio_gymbro(text, int, text)   from public;
revoke all on function public.panel_registro_gymbro(text, boolean)      from public;
revoke all on function public.bienvenida_crear_gymbro(text)             from public, anon, authenticated;
grant execute on function public.panel_gymbro(text)                        to anon, authenticated;
grant execute on function public.panel_alta_socio_gymbro(text, text, text) to anon, authenticated;
grant execute on function public.panel_estado_socio_gymbro(text, int, boolean) to anon, authenticated;
grant execute on function public.panel_rol_socio_gymbro(text, int, text)   to anon, authenticated;
grant execute on function public.panel_registro_gymbro(text, boolean)      to anon, authenticated;
grant execute on function public.bienvenida_crear_gymbro(text)             to service_role;

commit;
