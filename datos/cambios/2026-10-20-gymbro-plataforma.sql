-- =====================================================================
-- Gymbro · panel de plataforma de autonomIA Lab (20 oct 2026)
-- =====================================================================
-- Solo AÑADE funciones (no cambia tablas ni nada de MultiBar). Las usa
-- `/plataforma/` con la sesión de la cuenta de plataforma de Carlos
-- (`plataforma_entrar`, común a los paneles de todos los productos).
-- Ve los gimnasios (negocios de tipo `gymbro`), los da de alta con su
-- dueño (rol `admin`), los da de baja o reactiva y abre o cierra el
-- registro libre. No enseña pesos ni rutinas de nadie.
-- Se puede volver a ejecutar.
-- =====================================================================

begin;

-- Gimnasio por id (si no es de Gymbro: GIMNASIO_NO_VALIDO).
create or replace function privado.gimnasio_gymbro(p_id int)
returns comun.negocios
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  select * into n from comun.negocios where id = p_id and tipo = 'gymbro';
  if not found then
    raise exception 'GIMNASIO_NO_VALIDO';
  end if;
  return n;
end $$;

-- Números de un gimnasio (socios de la app, sin cuentas borradas).
create or replace function privado.cifras_gimnasio_gymbro(p_id int)
returns jsonb
language sql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
  select jsonb_build_object(
    'socios',      count(*) filter (where u.active and not u.must_change_password),
    'pendientes',  count(*) filter (where u.active and u.must_change_password),
    'de_baja',     count(*) filter (where not u.active),
    'admins',      count(*) filter (where u.active and so.rol = 'admin'),
    'activos_7d',  (select count(distinct e.usuario_id) from gymbro.entrenos_gymbro e
                     join gymbro.socios_gymbro s2 on s2.usuario_id = e.usuario_id
                    where s2.negocio_id = p_id and e.fecha >= current_date - 6),
    'entrenos_7d', (select count(*) from gymbro.entrenos_gymbro e
                     join gymbro.socios_gymbro s2 on s2.usuario_id = e.usuario_id
                    where s2.negocio_id = p_id and e.fecha >= current_date - 6),
    'entrenos_30d',(select count(*) from gymbro.entrenos_gymbro e
                     join gymbro.socios_gymbro s2 on s2.usuario_id = e.usuario_id
                    where s2.negocio_id = p_id and e.fecha >= current_date - 29),
    'ultimo',      (select max(e.fecha) from gymbro.entrenos_gymbro e
                     join gymbro.socios_gymbro s2 on s2.usuario_id = e.usuario_id
                    where s2.negocio_id = p_id))
    from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
   where so.negocio_id = p_id and u.email not like '%@cuenta-borrada.invalid'
$$;

-- Lista de gimnasios (activos primero).
create or replace function public.plataforma_gimnasios_gymbro(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
begin
  perform privado.plataforma_de_token(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', n.id, 'slug', n.slug, 'nombre', n.nombre, 'activo', n.activo,
            'alta', n.created_at, 'baja', n.baja_at,
            'registro_abierto', coalesce(a.registro_abierto, false),
            'cifras', privado.cifras_gimnasio_gymbro(n.id))
            order by n.activo desc, lower(n.nombre)), '[]'::jsonb)
            from comun.negocios n left join gymbro.ajustes_gymbro a on a.negocio_id = n.id
           where n.tipo = 'gymbro');
end $$;

-- Ficha de un gimnasio: datos, cifras y sus administradores (los socios
-- los gestiona el dueño en su panel).
create or replace function public.plataforma_gimnasio_gymbro(p_token text, p_id int)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  perform privado.plataforma_de_token(p_token);
  n := privado.gimnasio_gymbro(p_id);
  return privado.negocio_json_gymbro(n.id) || jsonb_build_object(
    'id', n.id, 'activo', n.activo, 'alta', n.created_at, 'baja', n.baja_at,
    'cifras', privado.cifras_gimnasio_gymbro(n.id),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', u.id, 'nombre', u.name, 'email', u.email, 'activo', u.active,
                 'pendiente', u.must_change_password) order by u.created_at), '[]'::jsonb)
                 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                where so.negocio_id = n.id and so.rol = 'admin'
                  and u.email not like '%@cuenta-borrada.invalid'));
end $$;

-- Alta de un gimnasio: negocio, Gymbro contratado, ajustes (registro libre
-- apagado salvo que se pida) y la cuenta del dueño con rol admin y una
-- contraseña al azar (la elige él con el correo de bienvenida). Todo o nada.
-- p_datos: {nombre, slug, email, dueno, registro_abierto?}
create or replace function public.plataforma_alta_gimnasio_gymbro(p_token text, p_datos jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare
  v_nombre text := btrim(coalesce(p_datos->>'nombre', ''));
  v_slug   text := lower(btrim(coalesce(p_datos->>'slug', '')));
  v_email  text := rtrim(lower(btrim(coalesce(p_datos->>'email', ''))), '.');
  v_dueno  text := btrim(coalesce(p_datos->>'dueno', ''));
  v_id int; v_uid int;
begin
  perform privado.plataforma_de_token(p_token);
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
end $$;

-- Dar de baja o reactivar un gimnasio (no borra nada; de baja, nadie entra
-- ni en la app ni en el panel del dueño).
create or replace function public.plataforma_estado_gimnasio_gymbro(p_token text, p_id int, p_activo boolean)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  perform privado.plataforma_de_token(p_token);
  if p_activo is null then
    raise exception 'FALTAN_DATOS';
  end if;
  n := privado.gimnasio_gymbro(p_id);
  update comun.negocios set activo = p_activo, baja_at = case when p_activo then null else now() end
   where id = n.id;
  update comun.productos_contratados set activo = p_activo where negocio_id = n.id and producto = 'gymbro';
  return jsonb_build_object('id', n.id, 'activo', p_activo);
end $$;

-- Abrir o cerrar el registro libre de un gimnasio.
create or replace function public.plataforma_registro_gymbro(p_token text, p_id int, p_abierto boolean)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  perform privado.plataforma_de_token(p_token);
  if p_abierto is null then
    raise exception 'FALTAN_DATOS';
  end if;
  n := privado.gimnasio_gymbro(p_id);
  insert into gymbro.ajustes_gymbro (negocio_id, registro_abierto) values (n.id, p_abierto)
  on conflict (negocio_id) do update set registro_abierto = excluded.registro_abierto, updated_at = now();
  return jsonb_build_object('id', n.id, 'registro_abierto', p_abierto);
end $$;

revoke all on function privado.gimnasio_gymbro(int)                          from public, anon, authenticated;
revoke all on function privado.cifras_gimnasio_gymbro(int)                   from public, anon, authenticated;
revoke all on function public.plataforma_gimnasios_gymbro(text)              from public;
revoke all on function public.plataforma_gimnasio_gymbro(text, int)          from public;
revoke all on function public.plataforma_alta_gimnasio_gymbro(text, jsonb)   from public;
revoke all on function public.plataforma_estado_gimnasio_gymbro(text, int, boolean) from public;
revoke all on function public.plataforma_registro_gymbro(text, int, boolean) from public;
grant execute on function public.plataforma_gimnasios_gymbro(text)              to anon, authenticated;
grant execute on function public.plataforma_gimnasio_gymbro(text, int)          to anon, authenticated;
grant execute on function public.plataforma_alta_gimnasio_gymbro(text, jsonb)   to anon, authenticated;
grant execute on function public.plataforma_estado_gimnasio_gymbro(text, int, boolean) to anon, authenticated;
grant execute on function public.plataforma_registro_gymbro(text, int, boolean) to anon, authenticated;

commit;
