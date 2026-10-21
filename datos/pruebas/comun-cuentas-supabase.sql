-- COPIA para las pruebas locales de Gymbro. El original es de AutonomIA-Lab
-- (datos/cambios/2026-10-21-cuentas-supabase.sql, rama ccr-66066c8f-u7w8ll) y ya
-- está aplicado en autonomialab-db: NO aplicarlo desde aquí.
-- autonomIA Lab · 21 oct 2026 · Todas las cuentas pasan al login de Supabase (decisión de Carlos, 21 oct).
-- Base: autonomialab-db (ref dorunbacwnkwdatfscri). Repositorio dueño: AutonomIA-Lab (carpetas comun y autonomialab).
--
-- Qué hace:
--  1. Cada cuenta de comun.usuarios (personal de bares, socios de gimnasio, cuenta de plataforma de Carlos) queda
--     enlazada a una cuenta de Supabase (auth.users) con LA MISMA contraseña cifrada (bcrypt). Su número de cuenta
--     no cambia, así que su historial (entrenos, pedidos…) sigue igual.
--  2. Mientras MultiBar y Gymbro pasan al login de Supabase, las dos copias se mantienen iguales solas:
--     si un producto da de alta, cambia la contraseña, el correo o da de baja una cuenta, se copia a Supabase;
--     si alguien cambia su contraseña con Supabase, se copia a comun.usuarios.
--  3. Carpeta autonomialab: miembros de la web, solicitudes de acceso y clientes (persona de la web ↔ su negocio).
--     Tablas cerradas: la web solo usa las funciones *_autonomialab, que comprueban quién llama.
--
-- Sin DELETE ni DROP (la conexión de Claude con Supabase los cancela). No toca ninguna tabla ni función de multibar ni de gymbro.
-- Se puede volver a aplicar sin romper nada (if not exists / or replace).

-- ---------------------------------------------------------------------------
-- 0. Ayuda común: limpiar un correo dictado («…@gmail.com. » → «…@gmail.com»), como piden las bases.
-- ---------------------------------------------------------------------------
create or replace function privado.limpiar_correo(p text) returns text
language sql immutable set search_path = ''
as $$ select lower(regexp_replace(btrim(coalesce(p, '')), '[\s.]+$', '')) $$;
revoke all on function privado.limpiar_correo(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Carpeta autonomialab (cerrada)
-- ---------------------------------------------------------------------------
create table if not exists autonomialab.miembros_autonomialab (
  auth_id   uuid primary key references auth.users (id) on delete cascade,
  nombre    text check (char_length(nombre) <= 120),
  creado_en timestamptz not null default now()
);
comment on table autonomialab.miembros_autonomialab is
  'Personas con acceso a la web de autonomIA Lab (membresía). No son personal de ningún negocio.';

create table if not exists autonomialab.solicitudes_acceso_autonomialab (
  id            uuid primary key default gen_random_uuid(),
  email         text not null check (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  token         uuid not null unique default gen_random_uuid(),
  estado        text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  tipo          text check (tipo in ('autonomo', 'pyme', 'empresa', 'otro')),
  sector        text check (char_length(sector) <= 60),
  nombre        text check (char_length(nombre) <= 120),
  telefono      text check (char_length(telefono) <= 30),
  mensaje       text check (char_length(mensaje) <= 1000),
  creado_en     timestamptz not null default now(),
  completada_en timestamptz
);
create index if not exists solicitudes_acceso_autonomialab_estado_idx
  on autonomialab.solicitudes_acceso_autonomialab (estado, creado_en desc);
create index if not exists solicitudes_acceso_autonomialab_email_idx
  on autonomialab.solicitudes_acceso_autonomialab (lower(email));
comment on table autonomialab.solicitudes_acceso_autonomialab is 'Peticiones de acceso a la web (solo correo + datos opcionales).';

create table if not exists autonomialab.clientes_autonomialab (
  auth_id    uuid primary key references autonomialab.miembros_autonomialab (auth_id) on delete cascade,
  negocio_id integer not null references comun.negocios (id),
  rol        text not null default 'empleado' check (rol in ('admin', 'empleado')),
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);
create index if not exists clientes_autonomialab_negocio_idx on autonomialab.clientes_autonomialab (negocio_id);
comment on table autonomialab.clientes_autonomialab is
  'Qué miembro de la web es cliente de qué negocio (uno solo). Le da acceso completo y «Tus aplicaciones».';

alter table autonomialab.miembros_autonomialab enable row level security;
alter table autonomialab.solicitudes_acceso_autonomialab enable row level security;
alter table autonomialab.clientes_autonomialab enable row level security;
revoke all on schema autonomialab from public, anon, authenticated;
revoke all on autonomialab.miembros_autonomialab, autonomialab.solicitudes_acceso_autonomialab,
  autonomialab.clientes_autonomialab from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Enlace de comun.usuarios con Supabase
-- ---------------------------------------------------------------------------
alter table comun.usuarios add column if not exists auth_id uuid unique references auth.users (id) on delete set null;
comment on column comun.usuarios.auth_id is 'Su cuenta de Supabase (misma contraseña). Se rellena sola.';

-- Crea o pone al día la cuenta de Supabase de una cuenta de comun.usuarios. Devuelve su id de Supabase.
create or replace function privado.cuenta_a_supabase(u comun.usuarios) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id    uuid := u.auth_id;
  v_email text := lower(btrim(u.email));
  v_baja  timestamptz := case when u.active then null else now() + interval '100 years' end;
begin
  if v_id is null then
    select au.id into v_id from auth.users au where lower(au.email) = v_email;
    -- Un correo = una cuenta: si ya es de otra persona (otra cuenta de negocio o un miembro de la web), no se mezcla.
    if v_id is not null and (
         exists (select 1 from comun.usuarios x where x.auth_id = v_id and x.id <> u.id)
      or exists (select 1 from autonomialab.miembros_autonomialab m where m.auth_id = v_id)) then
      raise exception 'CORREO_EN_USO' using hint = 'Ese correo ya tiene otra cuenta en autonomIA Lab.';
    end if;
  end if;

  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, banned_until,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email, u.password_hash, now(), v_baja,
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nombre', left(u.name, 120)), now(), now(),
      '', '', '', '', '', '', '', ''
    );
    insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
            'email', now(), now());
  else
    update auth.users au
       set email = v_email, encrypted_password = u.password_hash, banned_until = v_baja, updated_at = now()
     where au.id = v_id
       and (au.email is distinct from v_email or au.encrypted_password is distinct from u.password_hash
            or au.banned_until is distinct from v_baja);
    update auth.identities i
       set identity_data = i.identity_data || jsonb_build_object('email', v_email), updated_at = now()
     where i.user_id = v_id and i.provider = 'email' and i.identity_data ->> 'email' is distinct from v_email;
  end if;
  return v_id;
end;
$$;
revoke all on function privado.cuenta_a_supabase(comun.usuarios) from public, anon, authenticated;

-- Antes de guardar una cuenta de comun.usuarios: copiarla a Supabase y apuntar el enlace.
create or replace function privado.usuarios_a_supabase() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.auth_id is not null
     and new.email is not distinct from old.email and new.password_hash is not distinct from old.password_hash
     and new.active is not distinct from old.active and new.auth_id is not distinct from old.auth_id then
    return new;
  end if;
  new.auth_id := privado.cuenta_a_supabase(new);
  return new;
end;
$$;
revoke all on function privado.usuarios_a_supabase() from public, anon, authenticated;

create or replace trigger usuarios_a_supabase
  before insert or update of email, password_hash, active, auth_id on comun.usuarios
  for each row execute function privado.usuarios_a_supabase();

-- Si alguien cambia su contraseña con Supabase (recuperar, «nueva contraseña»), se copia a comun.usuarios.
create or replace function privado.contrasena_desde_supabase() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Si el cambio viene de comun.usuarios (disparador de arriba), ya está copiado: no volver a copiarlo.
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  if new.encrypted_password is distinct from old.encrypted_password and new.encrypted_password like '$2%' then
    update comun.usuarios u
       set password_hash = new.encrypted_password, must_change_password = false, failed_attempts = 0, locked_until = null
     where u.auth_id = new.id and u.password_hash is distinct from new.encrypted_password;
  end if;
  return new;
end;
$$;
revoke all on function privado.contrasena_desde_supabase() from public, anon, authenticated;

create or replace trigger contrasena_desde_supabase
  after update of encrypted_password on auth.users
  for each row execute function privado.contrasena_desde_supabase();

-- Pasar ya todas las cuentas que existen (el disparador hace el trabajo).
update comun.usuarios set auth_id = auth_id where auth_id is null;

-- ---------------------------------------------------------------------------
-- 3. Quién llama
-- ---------------------------------------------------------------------------
-- Rol «plataforma»: la cuenta de Supabase de una cuenta activa del negocio de tipo 'plataforma' (Carlos).
create or replace function privado.es_plataforma() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from comun.usuarios u join comun.negocios n on n.id = u.negocio_id
     where u.auth_id = auth.uid() and u.active and n.activo and n.tipo = 'plataforma');
$$;
revoke all on function privado.es_plataforma() from public, anon, authenticated;

create or replace function privado.exigir_plataforma_autonomialab() returns void
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.es_plataforma() then
    raise exception 'No tienes permiso para esto.';
  end if;
end;
$$;
revoke all on function privado.exigir_plataforma_autonomialab() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Funciones de la web (public, *_autonomialab)
-- ---------------------------------------------------------------------------

-- Visitante: deja su correo. Devuelve el código de su solicitud para el paso de datos opcionales.
create or replace function public.solicitar_acceso_autonomialab(p_email text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_email text := privado.limpiar_correo(p_email);
  v_token uuid;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then
    raise exception 'Revisa el correo: no parece válido.';
  end if;
  if exists (select 1 from autonomialab.miembros_autonomialab m join auth.users u on u.id = m.auth_id
              where lower(u.email) = v_email) then
    raise exception 'Ese correo ya tiene acceso. Entra con tu contraseña o usa «¿Olvidaste tu contraseña?».';
  end if;
  if exists (select 1 from comun.usuarios u where lower(u.email) = v_email) then
    raise exception 'Ese correo ya se usa en la aplicación de un negocio. Para esta web, usa otro correo.';
  end if;
  if (select count(*) from autonomialab.solicitudes_acceso_autonomialab s
       where s.creado_en > now() - interval '1 hour') >= 200 then
    raise exception 'Demasiadas solicitudes ahora mismo. Prueba más tarde.';
  end if;

  -- Si ya pidió acceso y sigue pendiente, se reutiliza su solicitud.
  select s.token into v_token from autonomialab.solicitudes_acceso_autonomialab s
   where lower(s.email) = v_email and s.estado = 'pendiente'
   order by s.creado_en desc limit 1;
  if v_token is null then
    insert into autonomialab.solicitudes_acceso_autonomialab (email) values (v_email) returning token into v_token;
  end if;
  return v_token;
end;
$$;

-- Visitante (opcional): datos del negocio, con el código de su solicitud. Solo mientras siga pendiente.
create or replace function public.completar_solicitud_autonomialab(
  p_token uuid, p_tipo text, p_sector text, p_nombre text, p_telefono text, p_mensaje text
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update autonomialab.solicitudes_acceso_autonomialab set
    tipo = case when p_tipo in ('autonomo', 'pyme', 'empresa', 'otro') then p_tipo end,
    sector = nullif(left(btrim(coalesce(p_sector, '')), 60), ''),
    nombre = nullif(left(btrim(coalesce(p_nombre, '')), 120), ''),
    telefono = nullif(left(btrim(coalesce(p_telefono, '')), 30), ''),
    mensaje = nullif(left(btrim(coalesce(p_mensaje, '')), 1000), ''),
    completada_en = now()
  where token = p_token and estado = 'pendiente';
  if not found then
    raise exception 'Esta solicitud ya no se puede modificar.';
  end if;
end;
$$;

-- Quién soy en la web: plataforma (Carlos), miembro (con su negocio si es cliente) o nada (cuenta de un negocio).
create or replace function public.yo_autonomialab() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_res jsonb;
begin
  if v_uid is null then
    return null;
  end if;
  if privado.es_plataforma() then
    select jsonb_build_object('tipo', 'plataforma', 'nombre', u.name, 'email', u.email, 'cliente', null)
      into v_res from comun.usuarios u where u.auth_id = v_uid;
    return v_res;
  end if;
  select jsonb_build_object(
           'tipo', 'miembro', 'nombre', m.nombre, 'email', au.email,
           'cliente', (
             select jsonb_build_object(
                      'negocio_id', n.id, 'nombre', n.nombre, 'tipo', n.tipo, 'rol', c.rol,
                      'productos', coalesce((select jsonb_agg(p.producto order by p.producto)
                                               from comun.productos_contratados p
                                              where p.negocio_id = n.id and p.activo), '[]'::jsonb))
               from autonomialab.clientes_autonomialab c join comun.negocios n on n.id = c.negocio_id
              where c.auth_id = m.auth_id and c.activo and n.activo))
    into v_res
    from autonomialab.miembros_autonomialab m join auth.users au on au.id = m.auth_id
   where m.auth_id = v_uid;
  return v_res;
end;
$$;

-- Plataforma: solicitudes pendientes.
create or replace function public.admin_solicitudes_autonomialab()
returns table (id uuid, email text, tipo text, sector text, nombre text, telefono text, mensaje text, creado_en timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform privado.exigir_plataforma_autonomialab();
  return query
    select s.id, s.email, s.tipo, s.sector, s.nombre, s.telefono, s.mensaje, s.creado_en
      from autonomialab.solicitudes_acceso_autonomialab s
     where s.estado = 'pendiente'
     order by s.creado_en desc;
end;
$$;

-- Plataforma: aprobar. Crea su cuenta de Supabase (sin contraseña) y su ficha de miembro.
-- Devuelve el correo para que la web le mande el enlace para crear su contraseña.
create or replace function public.admin_aprobar_acceso_autonomialab(p_solicitud uuid) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_email  text;
  v_nombre text;
  v_id     uuid;
begin
  perform privado.exigir_plataforma_autonomialab();
  select lower(s.email), s.nombre into v_email, v_nombre from autonomialab.solicitudes_acceso_autonomialab s
   where s.id = p_solicitud and s.estado = 'pendiente'
     for update;
  if v_email is null then
    raise exception 'Esa solicitud ya no está pendiente.';
  end if;
  if exists (select 1 from comun.usuarios u where lower(u.email) = v_email) then
    raise exception 'Ese correo ya es de una cuenta de un negocio. Pídele otro correo para la web.';
  end if;

  select au.id into v_id from auth.users au where lower(au.email) = v_email;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email, '', now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      case when v_nombre is null then '{}'::jsonb else jsonb_build_object('nombre', v_nombre) end,
      now(), now(), '', '', '', '', '', '', '', ''
    );
    insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
            'email', now(), now());
  end if;

  insert into autonomialab.miembros_autonomialab (auth_id, nombre) values (v_id, v_nombre)
  on conflict (auth_id) do nothing;
  update autonomialab.solicitudes_acceso_autonomialab set estado = 'aprobada' where id = p_solicitud;
  return v_email;
end;
$$;

create or replace function public.admin_rechazar_acceso_autonomialab(p_solicitud uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.exigir_plataforma_autonomialab();
  update autonomialab.solicitudes_acceso_autonomialab set estado = 'rechazada'
   where id = p_solicitud and estado = 'pendiente';
  if not found then
    raise exception 'Esa solicitud ya no está pendiente.';
  end if;
end;
$$;

-- Plataforma: miembros de la web.
create or replace function public.admin_miembros_autonomialab()
returns table (auth_id uuid, email text, nombre text, creado_en timestamptz, ha_entrado boolean, negocio text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform privado.exigir_plataforma_autonomialab();
  return query
    select m.auth_id, au.email::text, m.nombre, m.creado_en, au.last_sign_in_at is not null,
           (select n.nombre from autonomialab.clientes_autonomialab c join comun.negocios n on n.id = c.negocio_id
             where c.auth_id = m.auth_id and c.activo)
      from autonomialab.miembros_autonomialab m join auth.users au on au.id = m.auth_id
     order by m.creado_en desc
     limit 500;
end;
$$;

-- Plataforma: negocios (los clientes), con sus productos y cuántas personas de la web tienen.
create or replace function public.admin_clientes_autonomialab()
returns table (id integer, nombre text, slug text, tipo text, activo boolean, productos text[], personas bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform privado.exigir_plataforma_autonomialab();
  return query
    select n.id, n.nombre, n.slug, n.tipo, n.activo,
           coalesce((select array_agg(p.producto order by p.producto) from comun.productos_contratados p
                      where p.negocio_id = n.id and p.activo), '{}'),
           (select count(*) from autonomialab.clientes_autonomialab c where c.negocio_id = n.id and c.activo)
      from comun.negocios n
     where n.tipo <> 'plataforma'
     order by n.activo desc, n.created_at desc;
end;
$$;

-- Plataforma: ficha de un negocio.
create or replace function public.admin_cliente_autonomialab(p_negocio integer) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_res jsonb;
begin
  perform privado.exigir_plataforma_autonomialab();
  select jsonb_build_object(
           'id', n.id, 'nombre', n.nombre, 'slug', n.slug, 'tipo', n.tipo, 'activo', n.activo,
           'alta', n.created_at, 'titular', n.titular, 'nif', n.nif, 'correo_legal', n.correo_legal,
           'telefono_legal', n.telefono_legal,
           'cuentas_app', (select count(*) from comun.usuarios u where u.negocio_id = n.id and u.active),
           'productos', coalesce((select jsonb_agg(jsonb_build_object('producto', p.producto, 'activo', p.activo,
                                                                        'desde', p.desde) order by p.producto)
                                    from comun.productos_contratados p where p.negocio_id = n.id), '[]'::jsonb),
           'personas', coalesce((select jsonb_agg(jsonb_build_object('auth_id', c.auth_id, 'email', au.email,
                                                                       'nombre', m.nombre, 'rol', c.rol)
                                                  order by c.rol, au.email)
                                   from autonomialab.clientes_autonomialab c
                                   join autonomialab.miembros_autonomialab m on m.auth_id = c.auth_id
                                   join auth.users au on au.id = c.auth_id
                                  where c.negocio_id = n.id and c.activo), '[]'::jsonb))
    into v_res
    from comun.negocios n
   where n.id = p_negocio and n.tipo <> 'plataforma';
  return v_res;
end;
$$;

-- Plataforma: dar a un miembro de la web acceso de cliente a un negocio (por su correo).
create or replace function public.admin_anadir_persona_autonomialab(p_negocio integer, p_email text, p_rol text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id   uuid;
  v_otro integer;
begin
  perform privado.exigir_plataforma_autonomialab();
  if p_rol not in ('admin', 'empleado') then
    raise exception 'Papel no válido.';
  end if;
  if not exists (select 1 from comun.negocios n where n.id = p_negocio and n.tipo <> 'plataforma') then
    raise exception 'Ese negocio no existe.';
  end if;
  select m.auth_id into v_id from autonomialab.miembros_autonomialab m join auth.users au on au.id = m.auth_id
   where lower(au.email) = privado.limpiar_correo(p_email);
  if v_id is null then
    raise exception 'Ese correo todavía no tiene acceso a la web. Que lo solicite en autonomialab.es y apruébalo primero.';
  end if;
  select c.negocio_id into v_otro from autonomialab.clientes_autonomialab c where c.auth_id = v_id and c.activo;
  if v_otro is not null and v_otro <> p_negocio then
    raise exception 'Esa persona ya es cliente de otro negocio. Cada cuenta es de un solo negocio.';
  end if;
  insert into autonomialab.clientes_autonomialab (auth_id, negocio_id, rol, activo) values (v_id, p_negocio, p_rol, true)
  on conflict (auth_id) do update set negocio_id = excluded.negocio_id, rol = excluded.rol, activo = true;
end;
$$;

-- Plataforma: quitarle el acceso de cliente (la ficha se guarda apagada, no se borra).
create or replace function public.admin_quitar_persona_autonomialab(p_negocio integer, p_auth uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.exigir_plataforma_autonomialab();
  update autonomialab.clientes_autonomialab set activo = false
   where auth_id = p_auth and negocio_id = p_negocio and activo;
  if not found then
    raise exception 'Esa persona ya no tenía acceso a este negocio.';
  end if;
end;
$$;

-- Permisos: visitantes solo pueden pedir acceso; el resto, con sesión (y cada función comprueba quién es).
revoke all on function public.solicitar_acceso_autonomialab(text) from public;
revoke all on function public.completar_solicitud_autonomialab(uuid, text, text, text, text, text) from public;
revoke all on function public.yo_autonomialab() from public, anon;
revoke all on function public.admin_solicitudes_autonomialab() from public, anon;
revoke all on function public.admin_aprobar_acceso_autonomialab(uuid) from public, anon;
revoke all on function public.admin_rechazar_acceso_autonomialab(uuid) from public, anon;
revoke all on function public.admin_miembros_autonomialab() from public, anon;
revoke all on function public.admin_clientes_autonomialab() from public, anon;
revoke all on function public.admin_cliente_autonomialab(integer) from public, anon;
revoke all on function public.admin_anadir_persona_autonomialab(integer, text, text) from public, anon;
revoke all on function public.admin_quitar_persona_autonomialab(integer, uuid) from public, anon;

grant execute on function public.solicitar_acceso_autonomialab(text) to anon, authenticated;
grant execute on function public.completar_solicitud_autonomialab(uuid, text, text, text, text, text) to anon, authenticated;
grant execute on function public.yo_autonomialab() to authenticated;
grant execute on function public.admin_solicitudes_autonomialab() to authenticated;
grant execute on function public.admin_aprobar_acceso_autonomialab(uuid) to authenticated;
grant execute on function public.admin_rechazar_acceso_autonomialab(uuid) to authenticated;
grant execute on function public.admin_miembros_autonomialab() to authenticated;
grant execute on function public.admin_clientes_autonomialab() to authenticated;
grant execute on function public.admin_cliente_autonomialab(integer) to authenticated;
grant execute on function public.admin_anadir_persona_autonomialab(integer, text, text) to authenticated;
grant execute on function public.admin_quitar_persona_autonomialab(integer, uuid) to authenticated;
