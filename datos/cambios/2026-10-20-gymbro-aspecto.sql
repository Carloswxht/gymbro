-- =====================================================================
-- Gymbro · aspecto de cada gimnasio desde la base (20 oct 2026, v102)
-- =====================================================================
-- Hasta ahora el nombre, la frase, los colores y el icono de War300
-- estaban escritos en la app. Desde aquí salen de la base:
--   · `ajustes_gymbro.aspecto`: {lema, tema, colores?}
--       lema    → frase corta del gimnasio (para compartir y al instalar)
--       tema    → uno de los temas de la app ('theme-dark', 'theme-neon'…)
--                 o 'propio' con colores = {ink, day1, day2, day3} (#RRGGBB)
--   · `ajustes_gymbro.logo` (columna nueva): el logo, como ruta de un
--     archivo de la web ('/icons/icon-512.png') o como imagen PNG subida
--     desde `/plataforma/` ('data:image/png;base64,…', máx. 400 000 letras).
--     No va dentro de `negocio_gymbro` (pesaría en cada arranque): esa
--     función devuelve solo `logo_v` (huella corta) y la app pide el logo
--     con `logo_gymbro` cuando cambia.
-- Solo AÑADE (una columna con valor nulo y funciones nuevas) y amplía la
-- respuesta de `negocio_json_gymbro` con `logo_v` (las webs anteriores la
-- ignoran). Guarda los valores de hoy de War300 para que no cambie nada.
-- Se puede volver a ejecutar.
-- =====================================================================

begin;

alter table gymbro.ajustes_gymbro add column if not exists logo text;

-- Lo que la app necesita saber del negocio (nombre, aspecto, registro) y
-- la huella del logo (el logo se pide aparte con logo_gymbro).
create or replace function privado.negocio_json_gymbro(p_negocio int)
returns jsonb
language sql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
  select jsonb_build_object(
    'slug', n.slug, 'nombre', n.nombre, 'logo', n.logo,
    'aspecto', coalesce(a.aspecto, '{}'::jsonb),
    'logo_v', case when a.logo is not null then left(md5(a.logo), 12) end,
    'registro_abierto', coalesce(a.registro_abierto, false))
    from comun.negocios n left join gymbro.ajustes_gymbro a on a.negocio_id = n.id
   where n.id = p_negocio
$$;

-- Logo de un gimnasio activo (para la app, el panel del dueño y el icono).
create or replace function public.logo_gymbro(p_slug text)
returns jsonb
language plpgsql stable security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; v_logo text;
begin
  n := privado.negocio_gymbro(p_slug);
  select logo into v_logo from gymbro.ajustes_gymbro where negocio_id = n.id;
  return jsonb_build_object('logo', v_logo,
    'logo_v', case when v_logo is not null then left(md5(v_logo), 12) end);
end $$;

-- Comprueba y limpia el aspecto que manda /plataforma/ (solo se guarda lo
-- que se conoce; lo demás se descarta).
create or replace function privado.aspecto_limpio_gymbro(p_aspecto jsonb)
returns jsonb
language plpgsql immutable
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare
  v_lema text := btrim(coalesce(p_aspecto->>'lema', ''));
  v_tema text := btrim(coalesce(p_aspecto->>'tema', ''));
  v_col  jsonb := p_aspecto->'colores';
  r jsonb := '{}'::jsonb; k text;
begin
  if jsonb_typeof(coalesce(p_aspecto, 'null'::jsonb)) <> 'object' then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  if length(v_lema) > 80 then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  if v_lema <> '' then r := r || jsonb_build_object('lema', v_lema); end if;
  if v_tema = '' then
    return r;
  end if;
  if v_tema = 'propio' then
    if jsonb_typeof(coalesce(v_col, 'null'::jsonb)) <> 'object' then
      raise exception 'DATOS_NO_VALIDOS';
    end if;
    foreach k in array array['ink', 'day1', 'day2', 'day3'] loop
      if coalesce(v_col->>k, '') !~ '^#[0-9A-Fa-f]{6}$' then
        raise exception 'DATOS_NO_VALIDOS';
      end if;
    end loop;
    return r || jsonb_build_object('tema', 'propio', 'colores', jsonb_build_object(
      'ink', upper(v_col->>'ink'), 'day1', upper(v_col->>'day1'),
      'day2', upper(v_col->>'day2'), 'day3', upper(v_col->>'day3')));
  end if;
  if v_tema !~ '^theme-[a-z0-9-]{1,30}$' then
    raise exception 'DATOS_NO_VALIDOS';
  end if;
  return r || jsonb_build_object('tema', v_tema);
end $$;

-- Guardar nombre y aspecto de un gimnasio (solo la cuenta de plataforma).
-- p_datos: {nombre, lema?, tema?, colores?}
create or replace function public.plataforma_aspecto_gymbro(p_token text, p_id int, p_datos jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios; v_nombre text := btrim(coalesce(p_datos->>'nombre', '')); v_aspecto jsonb;
begin
  perform privado.plataforma_de_token(p_token);
  n := privado.gimnasio_gymbro(p_id);
  if v_nombre = '' or length(v_nombre) > 60 then
    raise exception 'FALTAN_DATOS';
  end if;
  v_aspecto := privado.aspecto_limpio_gymbro(p_datos);
  update comun.negocios set nombre = v_nombre where id = n.id;
  insert into gymbro.ajustes_gymbro (negocio_id, aspecto) values (n.id, v_aspecto)
  on conflict (negocio_id) do update set aspecto = excluded.aspecto, updated_at = now();
  return privado.negocio_json_gymbro(n.id);
end $$;

-- Cambiar o quitar el logo (null = sin logo: la app usa el de Gymbro).
create or replace function public.plataforma_logo_gymbro(p_token text, p_id int, p_logo text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare n comun.negocios;
begin
  perform privado.plataforma_de_token(p_token);
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
end $$;

-- La ficha de /plataforma/ lleva también el logo (para verlo y cambiarlo).
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
    'cifras', privado.cifras_gimnasio_gymbro(n.id),
    'admins', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', u.id, 'nombre', u.name, 'email', u.email, 'activo', u.active,
                 'pendiente', u.must_change_password) order by u.created_at), '[]'::jsonb)
                 from gymbro.socios_gymbro so join comun.usuarios u on u.id = so.usuario_id
                where so.negocio_id = n.id and so.rol = 'admin'
                  and u.email not like '%@cuenta-borrada.invalid'));
end $$;

-- War300 conserva lo que tenía escrito en la app (solo si aún no tiene
-- aspecto ni logo: no pisa lo que se cambie luego desde /plataforma/).
update gymbro.ajustes_gymbro a
   set aspecto = '{"lema": "La competencia es contra ti mismo.", "tema": "theme-dark"}'::jsonb,
       updated_at = now()
  from comun.negocios n
 where n.id = a.negocio_id and n.slug = 'war300' and n.tipo = 'gymbro' and a.aspecto = '{}'::jsonb;
update gymbro.ajustes_gymbro a
   set logo = '/icons/icon-512.png', updated_at = now()
  from comun.negocios n
 where n.id = a.negocio_id and n.slug = 'war300' and n.tipo = 'gymbro' and a.logo is null;

revoke all on function privado.aspecto_limpio_gymbro(jsonb)                   from public, anon, authenticated;
revoke all on function public.logo_gymbro(text)                               from public;
revoke all on function public.plataforma_aspecto_gymbro(text, int, jsonb)     from public;
revoke all on function public.plataforma_logo_gymbro(text, int, text)         from public;
grant execute on function public.logo_gymbro(text)                            to anon, authenticated;
grant execute on function public.plataforma_aspecto_gymbro(text, int, jsonb)  to anon, authenticated;
grant execute on function public.plataforma_logo_gymbro(text, int, text)      to anon, authenticated;

commit;
