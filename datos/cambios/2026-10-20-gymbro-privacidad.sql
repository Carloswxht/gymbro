-- =====================================================================
-- Gymbro · privacidad y aviso legal de cada gimnasio (20 oct 2026, v104)
-- =====================================================================
-- Cada gimnasio es el responsable de los datos de sus socios y autonomIA
-- Lab los guarda por encargo suyo. Esto añade:
--   · `consentimientos_gymbro`: quién aceptó qué versión de la privacidad
--     y cuándo (se conserva aunque la cuenta se borre: es la prueba).
--   · `legal_gymbro(slug)`: los datos para la página /legal/ (titular del
--     gimnasio, de `comun.negocios`, y autonomIA Lab como encargado).
--   · `legal_estado_gymbro` y `aceptar_legal_gymbro`: la app pregunta si
--     el socio aceptó la versión vigente y, si no, se la pide.
--   · `plataforma_legal_gymbro`: Carlos rellena los datos legales de cada
--     gimnasio desde /plataforma/; la ficha los trae en `legal`.
-- Solo AÑADE (una tabla y funciones nuevas) y amplía la respuesta de
-- `plataforma_gimnasio_gymbro`. Se puede volver a ejecutar.
-- Al cambiar el texto de la privacidad: subir la versión de
-- `privado.version_legal_gymbro` (todos la vuelven a aceptar) y la de
-- `legal/index.html`.
-- =====================================================================

begin;

create table if not exists gymbro.consentimientos_gymbro (
  usuario_id  int  not null references comun.usuarios(id),
  negocio_id  int  not null references comun.negocios(id),
  version     text not null check (length(version) between 1 and 20),
  aceptado_at timestamptz not null default now(),
  primary key (usuario_id, version)
);
alter table gymbro.consentimientos_gymbro enable row level security;
revoke all on gymbro.consentimientos_gymbro from public, anon, authenticated;

-- Versión vigente de la privacidad y el aviso legal de Gymbro.
create or replace function privado.version_legal_gymbro()
returns text
language sql immutable
set search_path = public, comun, gymbro, privado, pg_temp
as $$ select '2026-10-20'::text $$;

-- Datos legales de un negocio (gimnasio o autonomIA Lab).
create or replace function privado.datos_legales_gymbro(p_negocio int)
returns jsonb
language sql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
  select jsonb_build_object('nombre', n.nombre, 'titular', n.titular, 'nif', n.nif,
    'domicilio', n.domicilio_fiscal, 'correo', n.correo_legal, 'telefono', n.telefono_legal)
    from comun.negocios n where n.id = p_negocio
$$;

-- Lo que enseña la página /legal/?g=SLUG (gimnasio activo).
create or replace function public.legal_gymbro(p_slug text)
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; g jsonb;
begin
  n := privado.negocio_gymbro(p_slug);
  g := privado.datos_legales_gymbro(n.id);
  return jsonb_build_object(
    'version', privado.version_legal_gymbro(),
    'slug', n.slug,
    'gimnasio', g,
    'completo', coalesce(g->>'titular', '') <> '' and coalesce(g->>'nif', '') <> ''
                and coalesce(g->>'domicilio', '') <> '' and coalesce(g->>'correo', '') <> '',
    'encargado', coalesce((select privado.datos_legales_gymbro(id) from comun.negocios
                            where slug = 'autonomialab' and tipo = 'plataforma'),
                          jsonb_build_object('nombre', 'autonomIA Lab')));
end $$;

-- ¿Ha aceptado este socio la versión vigente?
create or replace function public.legal_estado_gymbro(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro; v text := privado.version_legal_gymbro(); a timestamptz;
begin
  s := privado.socio_de_token_gymbro(p_token);
  select aceptado_at into a from gymbro.consentimientos_gymbro where usuario_id = s.usuario_id and version = v;
  return jsonb_build_object('version', v, 'aceptada', a is not null, 'aceptada_at', a);
end $$;

-- El socio acepta la versión que ha visto (si ya no es la vigente, no vale).
create or replace function public.aceptar_legal_gymbro(p_token text, p_version text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare s gymbro.socios_gymbro;
begin
  s := privado.socio_de_token_gymbro(p_token);
  if p_version is distinct from privado.version_legal_gymbro() then
    raise exception 'VERSION_NO_VALIDA';
  end if;
  insert into gymbro.consentimientos_gymbro (usuario_id, negocio_id, version)
  values (s.usuario_id, s.negocio_id, p_version)
  on conflict (usuario_id, version) do nothing;
  return public.legal_estado_gymbro(p_token);
end $$;

-- Datos legales de un gimnasio (solo la cuenta de plataforma).
-- p_datos: {titular, nif, domicilio, correo, telefono?}; vacío = sin dato.
create or replace function public.plataforma_legal_gymbro(p_token text, p_id int, p_datos jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare
  n comun.negocios;
  v_titular text := nullif(btrim(coalesce(p_datos->>'titular', '')), '');
  v_nif     text := nullif(upper(regexp_replace(coalesce(p_datos->>'nif', ''), '[\s.-]', '', 'g')), '');
  v_dom     text := nullif(btrim(coalesce(p_datos->>'domicilio', '')), '');
  v_correo  text := nullif(rtrim(lower(btrim(coalesce(p_datos->>'correo', ''))), '.'), '');
  v_tel     text := nullif(btrim(coalesce(p_datos->>'telefono', '')), '');
begin
  perform privado.plataforma_de_token(p_token);
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
end $$;

-- La ficha de /plataforma/ lleva también los datos legales.
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
    'logo_gymbro', (select logo from gymbro.ajustes_gymbro where negocio_id = n.id),
    'legal', privado.datos_legales_gymbro(n.id),
    'cifras', privado.cifras_gimnasio_gymbro(n.id),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', u.id, 'nombre', u.name, 'email', u.email, 'activo', u.active,
                 'pendiente', u.must_change_password) order by u.created_at), '[]'::jsonb)
                 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                where so.negocio_id = n.id and so.rol = 'admin'
                  and u.email not like '%@cuenta-borrada.invalid'));
end $$;

revoke all on function privado.version_legal_gymbro()                       from public, anon, authenticated;
revoke all on function privado.datos_legales_gymbro(int)                    from public, anon, authenticated;
revoke all on function public.legal_gymbro(text)                            from public;
revoke all on function public.legal_estado_gymbro(text)                     from public;
revoke all on function public.aceptar_legal_gymbro(text, text)              from public;
revoke all on function public.plataforma_legal_gymbro(text, int, jsonb)     from public;
grant execute on function public.legal_gymbro(text)                         to anon, authenticated;
grant execute on function public.legal_estado_gymbro(text)                  to anon, authenticated;
grant execute on function public.aceptar_legal_gymbro(text, text)           to anon, authenticated;
grant execute on function public.plataforma_legal_gymbro(text, int, jsonb)  to anon, authenticated;

commit;
