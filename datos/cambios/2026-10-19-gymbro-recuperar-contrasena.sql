-- =====================================================================
-- Gymbro · recuperar la contraseña por correo (19 oct 2026)
-- =====================================================================
-- Solo AÑADE dos funciones. No toca nada de MultiBar ni de `comun`
-- (usa privado.crear_enlace, el ayudante común de enlaces: 30 min, un
-- solo uso, máx. 3 por hora). Se puede volver a ejecutar.
--
-- Flujo: la app manda el correo a la Edge Function
-- «recuperar-contrasena-gymbro» → esta llama a recuperar_crear_gymbro
-- (solo service_role) y manda el correo con Resend → el enlace abre la app
-- con #recuperar=CÓDIGO → la app llama a restablecer_gymbro.
-- =====================================================================

begin;

-- Crea el enlace (solo el servidor). Devuelve null si el correo no es de
-- una cuenta activa de un negocio de Gymbro activo, o si ya pidió 3 en 1 h.
create or replace function public.recuperar_crear_gymbro(p_email text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare u comun.usuarios; n comun.negocios; v_token text;
begin
  select us.* into u
    from comun.usuarios us join gymbro.socios_gymbro so on so.usuario_id = us.id
   where lower(us.email) = lower(btrim(coalesce(p_email, ''))) and us.active;
  if not found then
    return null;
  end if;
  select * into n from comun.negocios where id = u.negocio_id and tipo = 'gymbro' and activo;
  if not found then
    return null;
  end if;
  v_token := privado.crear_enlace(u.id, 30);
  if v_token is null then
    return null;
  end if;
  return jsonb_build_object('token', v_token, 'email', u.email, 'nombre', u.name,
                            'negocio_nombre', n.nombre, 'negocio_slug', n.slug);
end $$;

-- Elige contraseña nueva con el código del enlace (la web). Quita el
-- bloqueo por fallos y cierra todas sus sesiones.
create or replace function public.restablecer_gymbro(p_token text, p_nueva text)
returns jsonb
language plpgsql security definer
set search_path = public, comun, gymbro, privado, pg_temp
as $$
declare r comun.recuperaciones; v_email text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'ENLACE_NO_VALIDO';
  end if;
  select * into r from comun.recuperaciones
   where token_hash = privado.digest(p_token, 'sha256') for update;
  if not found or r.usado_at is not null or r.expires_at < now()
     or not exists (select 1 from gymbro.socios_gymbro where usuario_id = r.usuario_id) then
    raise exception 'ENLACE_NO_VALIDO';
  end if;
  if length(coalesce(p_nueva, '')) < 8 or length(p_nueva) > 72 then
    raise exception 'PASSWORD_CORTA';
  end if;
  update comun.usuarios set password_hash = privado.crypt(p_nueva, privado.gen_salt('bf', 10)),
                            must_change_password = false, failed_attempts = 0, locked_until = null
   where id = r.usuario_id and active
  returning email into v_email;
  if v_email is null then
    raise exception 'ENLACE_NO_VALIDO';
  end if;
  update comun.recuperaciones set usado_at = now() where token_hash = r.token_hash;
  update comun.sesiones set expires_at = now() where usuario_id = r.usuario_id and expires_at > now();
  return jsonb_build_object('email', v_email);
end $$;

revoke all on function public.recuperar_crear_gymbro(text)    from public, anon, authenticated;
grant execute on function public.recuperar_crear_gymbro(text) to service_role;
revoke all on function public.restablecer_gymbro(text, text)    from public;
grant execute on function public.restablecer_gymbro(text, text) to anon, authenticated;

commit;
