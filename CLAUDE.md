# Gymbro

@PLATAFORMA.md

> Las bases comunes de autonomIA Lab están en `PLATAFORMA.md` (copia idéntica de la maestra de `Carloswxht/AutonomIA-Lab`; no se cambia aquí). Donde este archivo contradiga a `PLATAFORMA.md`, gana `PLATAFORMA.md`.

## Qué es esto
- **Gymbro** es el gremio de rutinas de gimnasio de autonomIA Lab (decisión de Carlos, 19 oct). Sin relación con MultiBar: solo comparte la base `autonomialab-db`, la lista de negocios y las tablas de cuentas.
- **War300 es su primer cliente** (como La Mar de Gambas en MultiBar). Ficha en `datos/clientes/war300/NOTAS.md`.
- Repositorio `Carloswxht/gymbro` (antes `war300`, renombrado por Carlos el 19 oct). Dirección prevista: `gymbro.autonomialab.es` (GitHub Pages). Hoy la app de War300 está en Cloudflare: se quita cuando la nueva funcione.
- App: `index.html` (una sola página, instalable: `manifest.json`, `sw.js`). Última versión: **v96**, todavía sobre el Supabase propio «War300» (`pvcjolgqegthmudsvvlr`, Supabase Auth). La v97 pasará a `autonomialab-db`.

## Base de datos (carpeta `gymbro`, sufijo `_gymbro`)
- SQL en `datos/cambios/`. Pruebas en local: `datos/pruebas/replica-local.sql` (copia mínima de `comun` y del login de MultiBar) + `datos/pruebas/2026-10-19-gymbro-carpeta.sql`.
- Tablas: `ajustes_gymbro` (aspecto, opciones, `registro_abierto`), `socios_gymbro` (rol `socio`/`admin`), `progreso_gymbro`, `entrenos_gymbro` (antes `sesiones`), `ejercicios_personalizados_gymbro`.
- Cuentas en `comun.usuarios` (una por negocio). Funciones propias de entrar: `entrar_gymbro`, `registrar_gymbro`, `yo_gymbro`, `salir_gymbro`, `cambiar_password_gymbro`, `borrar_mi_cuenta_gymbro`; datos: `negocio_gymbro`, `mis_datos_gymbro`, `guardar_progreso_gymbro`, `mis_entrenos_gymbro`, `guardar_entreno_gymbro`, `guardar_personalizado_gymbro`. Sesiones de 60 días que se alargan al usar la app.
- Las funciones de MultiBar (`personal_entrar`…) no ven cuentas de Gymbro y al revés (probado).

## Plan (19 oct, con el «sí» de Carlos)
1. ✅ Bases v9 con Gymbro. ✅ SQL de la carpeta `gymbro` escrito y probado en local (`2026-10-19-gymbro-carpeta.sql`). ✅ **Aplicado en Supabase el 19 oct** (pegado por Carlos): 5 tablas y 16 funciones, huella `0e77c4908058072e79c386bdf4b8598b` idéntica a la copia probada; la web (anon) no ve la carpeta ni los ayudantes.
2. Alta de War300 (negocio `war300`, tipo `gymbro`, registro abierto, `productos_contratados`) y copia de datos: 2 cuentas con su contraseña (la de Carlos pasa a `carloswxht+war300@gmail.com`), 238 filas de progreso, 1 entreno. El único vídeo del bucket no lo usa ningún ejercicio: no se copia.
3. App v97: login y guardado con las funciones `_gymbro`; marca de War300 desde sus ajustes. Pendientes: recuperar contraseña por correo (función + Edge Function propias) y subida de vídeos (Edge Function; hoy el bucket de War300 está abierto a cualquiera).
4. Panel de plataforma `/plataforma/` (Carlos) y panel del dueño (rol `admin`).
5. Publicar en `gymbro.autonomialab.es`, aviso en la app vieja, quitar Cloudflare y pausar el Supabase «War300».
