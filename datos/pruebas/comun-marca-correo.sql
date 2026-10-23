-- COPIA de AutonomIA-Lab (datos/cambios/2026-10-23-marca-correo.sql, rama ccr-73e2782b-k4g7ub, 23 oct) solo para
-- probar en local. No aplicarla desde aquí: es de la carpeta comun (dueño AutonomIA-Lab).

-- autonomIA Lab · 23 oct 2026 · Correos de las cuentas con la imagen de cada negocio (decisión de Carlos, 23 oct).
-- Base: autonomialab-db (ref dorunbacwnkwdatfscri). Repositorio dueño: AutonomIA-Lab (carpeta comun).
--
-- Qué hace: public.marca_correo(auth_id) dice a la Edge Function «enviar-correo» con qué imagen sale el correo
-- de una persona: la de su negocio (nombre, logo, colores, correo para responder) o la de autonomIA Lab
-- (miembros de la web y cuenta de plataforma). Solo la puede llamar la Edge Function (service_role).
--
-- Cada producto pone sus colores y su logo, desde su repositorio, con una función propia:
--   public.marca_correo_<tipo>(p_negocio integer) returns jsonb   -- p. ej. marca_correo_multibar
--   claves (todas opcionales): nombre, logo (https), fondo, tarjeta, texto, acento (#RRGGBB), responder_a (correo)
--   security definer, search_path = '', execute solo para service_role.
-- Mientras un producto no la tenga, sus correos salen con el nombre y el logo de comun.negocios y los colores de
-- autonomIA Lab. Si su función falla, igual: el correo nunca se queda sin mandar.
--
-- Sin DELETE ni DROP. No toca ninguna tabla ni función de multibar ni de gymbro. Se puede volver a aplicar.

create or replace function public.marca_correo(p_auth_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_neg comun.negocios;
  v_persona text;
  v_marca jsonb;
  v_extra jsonb;
  v_funcion text;
begin
  select u.name into v_persona from comun.usuarios u where u.auth_id = p_auth_id;
  select n.* into v_neg
    from comun.usuarios u join comun.negocios n on n.id = u.negocio_id
   where u.auth_id = p_auth_id;

  -- Miembros de la web y cuenta de plataforma: imagen de autonomIA Lab.
  if v_neg.id is null or v_neg.tipo = 'plataforma' then
    if v_persona is null then
      select m.nombre into v_persona from autonomialab.miembros_autonomialab m where m.auth_id = p_auth_id;
    end if;
    return jsonb_strip_nulls(jsonb_build_object('marca', 'autonomialab', 'persona', v_persona));
  end if;

  v_marca := jsonb_build_object(
    'marca', 'negocio', 'producto', v_neg.tipo, 'nombre', v_neg.nombre, 'persona', v_persona,
    'logo', case when v_neg.logo ~ '^https://' then v_neg.logo end,
    'responder_a', nullif(btrim(v_neg.correo_legal), ''));

  -- Colores y logo propios del producto, si ya tiene su función.
  v_funcion := 'marca_correo_' || v_neg.tipo;
  if v_neg.tipo ~ '^[a-z0-9_]+$' and to_regprocedure(format('public.%I(integer)', v_funcion)) is not null then
    begin
      execute format('select public.%I($1)', v_funcion) into v_extra using v_neg.id;
      if jsonb_typeof(v_extra) = 'object' then
        v_marca := v_marca || jsonb_strip_nulls(
          jsonb_build_object(
            'nombre', v_extra->>'nombre', 'logo', v_extra->>'logo', 'fondo', v_extra->>'fondo',
            'tarjeta', v_extra->>'tarjeta', 'texto', v_extra->>'texto', 'acento', v_extra->>'acento',
            'responder_a', v_extra->>'responder_a'));
      end if;
    exception when others then
      raise warning 'marca_correo: % falló (%)', v_funcion, sqlerrm;
    end;
  end if;

  return jsonb_strip_nulls(v_marca);
end;
$$;
revoke all on function public.marca_correo(uuid) from public, anon, authenticated;
grant execute on function public.marca_correo(uuid) to service_role;
