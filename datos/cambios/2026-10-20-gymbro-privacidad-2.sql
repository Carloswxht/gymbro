-- =====================================================================
-- Gymbro · privacidad, versión 2026-10-20.2 (20 oct 2026, v105)
-- =====================================================================
-- La app ya no usa Google Fonts (letras guardadas en la web), así que el
-- texto de /legal/ deja de nombrar a Google. Al cambiar el texto se sube
-- la versión: todos los socios lo vuelven a aceptar una vez.
-- Solo cambia la versión que devuelve `privado.version_legal_gymbro`
-- (la misma que `VERSION_TEXTO` de legal/index.html). Se puede repetir.
-- =====================================================================

begin;

create or replace function privado.version_legal_gymbro()
returns text
language sql immutable
set search_path = public, comun, gymbro, privado, pg_temp
as $$ select '2026-10-20.2'::text $$;

revoke all on function privado.version_legal_gymbro() from public, anon, authenticated;

commit;
