#!/bin/sh
# Monta desde cero la base local «login» (v107): copia mínima de Supabase con
# su carpeta auth, la parte común de las cuentas de Supabase (copia de
# AutonomIA-Lab), todos los cambios de Gymbro y los datos de prueba.
# Postgres 16 en /var/tmp/gympg, puerto 5445 (ver CLAUDE.md).
set -e
cd "$(dirname "$0")/../.."
P="psql -h /var/tmp/gympg -p 5445 -U postgres -q -v ON_ERROR_STOP=1"
$P -c "drop database if exists login" -c "create database login"
P="$P -d login"
sed '/^create role anon/d' datos/pruebas/replica-local.sql | $P >/dev/null   # los roles ya existen en el servidor
$P -f datos/pruebas/replica-auth.sql
$P -f datos/pruebas/comun-cuentas-supabase.sql
for f in datos/cambios/2026-*.sql; do $P -f "$f" >/dev/null; done
$P -f datos/pruebas/datos-prueba-gymbro.sql
echo "base login lista"
