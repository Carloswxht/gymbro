-- =====================================================================
-- Gymbro · colores y logo de los correos de las cuentas (23 oct 2026)
-- =====================================================================
-- Encargo de AutonomIA-Lab (docs/correos-productos.md): los correos del
-- login de Supabase (cambiar contraseña…) los manda la Edge Function común
-- «enviar-correo», que pregunta a public.marca_correo(auth_id) con qué
-- imagen sale. Esa función común llama sola a esta si existe y le añade el
-- nombre del gimnasio (comun.negocios.nombre) y el correo para responder.
--
-- Aquí: el logo y los colores del gimnasio, los mismos que ve el socio en
-- la app por defecto (ajustes_gymbro):
--   · logo: ruta de la web (/icons/…png) → dirección https completa; sin
--     logo, el icono de Gymbro (como la app); un logo subido desde el móvil
--     (data:image/png;base64,…) no vale en un correo: sin logo (sale el
--     nombre) y, si comun.negocios.logo es https, la común usa ese.
--   · colores: fondo = el del tema (o «Propios»), acento (botón y franja) =
--     el color del día 1, el de la app. El texto y la tarjeta los saca la
--     común del fondo (y los corrige si no se leen).
-- La lista de temas es copia de TEMAS de plataforma/index.html (y de los
-- temas de index.html): si se añade uno allí, añadirlo aquí.
--
-- Solo la llama service_role. Sin DELETE ni DROP; se puede repetir.
-- =====================================================================

begin;

create or replace function public.marca_correo_gymbro(p_negocio integer)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with a as (
    select coalesce(x.aspecto, '{}'::jsonb) as aspecto, x.logo
      from gymbro.ajustes_gymbro x where x.negocio_id = p_negocio
  ), t(tema, fondo, acento) as (values
    ('theme-dark', '#0E1013', '#FF8A3D'), ('theme-light', '#FFFFFF', '#FF6B1A'),
    ('theme-neon', '#170526', '#FF2E9A'), ('theme-fire', '#2B0D00', '#FF5100'),
    ('theme-rave', '#0B140B', '#39FF14'), ('theme-ironhack', '#1B0B3F', '#6EFFC7'),
    ('theme-cyberpink', '#26082E', '#E91E8C'), ('theme-aedia', '#F6F5FA', '#3D1E96'),
    ('theme-developers', '#08090C', '#F2C230'), ('theme-core', '#170A06', '#FF5E3A'),
    ('theme-gol', '#04102E', '#E31C2B'), ('theme-tektag', '#0B0713', '#F4D03F'),
    ('theme-skvot', '#100D12', '#33FF6E'), ('theme-founderz', '#0F2B2B', '#E8442C'),
    ('theme-ionos', '#0A1F4D', '#17C9E8'), ('theme-ufvfilm', '#140A08', '#E8A33D'),
    ('theme-ebis', '#0B2530', '#1ABC9C'), ('theme-tealorange', '#0A1414', '#FF7A30'),
    ('theme-noir', '#0A0A0A', '#E8102A'), ('theme-wes', '#F2E4D0', '#F2A65A'),
    ('theme-bladerunner', '#0D0221', '#FF2EC4'), ('theme-rank-recluta', '#101214', '#9CA3AF'),
    ('theme-rank-soldado', '#14150F', '#CD7F32'), ('theme-rank-sargento', '#0E1216', '#C7CBD1'),
    ('theme-rank-capitan', '#0D0A05', '#FFD700'), ('theme-rank-general', '#050912', '#7DE2FF')
  ), c as (
    -- Sin fila de ajustes o sin tema: el Original (theme-dark), como la app.
    select case when a.aspecto->>'tema' = 'propio' then a.aspecto->'colores'->>'ink'
                else coalesce(t.fondo, '#0E1013') end as fondo,
           case when a.aspecto->>'tema' = 'propio' then a.aspecto->'colores'->>'day1'
                else coalesce(t.acento, '#FF8A3D') end as acento,
           a.logo
      from (select 1) uno
      left join a on true
      left join t on t.tema = a.aspecto->>'tema'
  )
  select jsonb_strip_nulls(jsonb_build_object(
    'logo', case
      when c.logo is null or btrim(c.logo) = '' then 'https://gymbro.autonomialab.es/icons/gymbro-512.png'
      when c.logo ~ '^/[A-Za-z0-9/._-]+$' then 'https://gymbro.autonomialab.es' || c.logo
      when c.logo ~ '^https://' then c.logo
    end,
    'fondo',  case when c.fondo  ~ '^#[0-9A-Fa-f]{6}$' then upper(c.fondo)  end,
    'acento', case when c.acento ~ '^#[0-9A-Fa-f]{6}$' then upper(c.acento) end))
  from c
  where exists (select 1 from comun.negocios n where n.id = p_negocio and n.tipo = 'gymbro');
$$;

revoke all on function public.marca_correo_gymbro(integer) from public, anon, authenticated;
grant execute on function public.marca_correo_gymbro(integer) to service_role;

commit;
