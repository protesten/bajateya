# Seguimiento del proyecto — Bájate Aquí

Registro vivo de lo que se va construyendo. Cada elemento terminado incluye
descripción, características y detalles técnicos para poder valorar el avance.
Última actualización: **2026-09-28** (fase alarma en 2º plano completada).

Leyenda: ✅ hecho · 🚧 en curso · ⬜ pendiente

---

## Resumen de estado

| Bloque | Estado |
|---|---|
| Análisis app oficial TITSA | ✅ |
| Fuentes de datos (GTFS + tiempo real) | ✅ verificadas |
| Procesador GTFS → SQLite | ✅ |
| Cliente tiempo real (SAE) | ✅ |
| Motor de alarma de bajada (lógica) | ✅ con tests |
| Esqueleto app Flutter | ✅ |
| **Alarma en segundo plano + notificaciones** | ✅ compila (APK generado) |
| **Actualización de datos (GTFS) + versionado** | ✅ implementado |
| **Consentimiento de descarga + ajustes** | ✅ implementado (APK ok) |
| **Repositorio en GitHub + CI de datos** | ✅ subido (protesten/bajateya) |
| **Primera release de datos publicada** | ✅ release `gtfs` (verificada) |
| Mapa (paradas + trazado) | ⬜ |
| Favoritos locales | ⬜ |
| Planificador de rutas | ⬜ |
| Multidioma | ⬜ |
| Publicación / clave idApp definitiva | ⬜ |

---

## ✅ Completado

### 1. Análisis de la app oficial de TITSA
- **Qué es:** ingeniería inversa de `com.titsa.app.android` v2.0.4 (jadx).
- **Detalle:** app Java nativa, Realm, Google Maps, Firebase. 121 clases propias.
- **Hallazgo clave:** su "alarma" NO es de bajada (solo push programado por hora).
  Sin modo offline, sin planificador, sin posición de guaguas en mapa.
- **Documentos:** `docs/01-analisis-app-titsa.md`, `docs/02-api-titsa.md`,
  `docs/03-competencia.md`, `docs/04-propuesta-app.md`.

### 2. Fuentes de datos (verificadas)
- **Estático:** GTFS oficial del Cabildo (CC-BY). 3.897 paradas, 181 líneas,
  51.219 expediciones, 854 trazados. Descargado y comprobado.
- **Tiempo real:** SAE `apps.titsa.com/apps/apps_sae_llegadas_parada.asp`.
  Probado en vivo con la `idApp` autorizada → responde XML con líneas y minutos.
- **Credenciales:** solo se usa `idApp` (en `config/secrets.env`, fuera de git).
  No se usan el usuario/contraseña OAuth del APK (los sustituye el GTFS).

### 3. Procesador GTFS → SQLite  (`tools/build_gtfs_db.py`)
- **Qué hace:** descarga el GTFS y genera `data/guaguas.sqlite` listo para empaquetar.
- **Características:**
  - Compresión por **patrones**: agrupa expediciones con la misma secuencia de
    paradas y offsets de tiempo → 51.219 expediciones = 3.962 patrones.
  - Simplificación de trazados **Douglas-Peucker** (~9 m tolerancia):
    774.080 → 134.252 puntos.
  - Resultado: **15,8 MB** (desde 52,5 MB sin optimizar).
  - Tablas: `stops`, `routes`, `patterns`, `pattern_stops` (con offset de tiempo
    y hueco para distancia sobre trazado), `trips`, `service_dates`, `shape_points`.
  - Índices para búsquedas por parada, patrón, línea y proximidad.

### 4. Cliente de tiempo real  (`app/lib/data/titsa_realtime.dart`)
- **Qué hace:** consulta llegadas de una parada al SAE y parsea el XML.
- **Detalle:** clase `TitsaRealtime`, modelo `Arrival` (línea, destino, sentido,
  minutos). `idApp` inyectada por configuración, nunca incrustada. Ordena por
  minutos. Timeout configurable.

### 5. Acceso a la base GTFS  (`app/lib/data/gtfs_db.dart`)
- **Qué hace:** copia el asset SQLite a almacenamiento y lo consulta en solo lectura.
- **Métodos:** `nearbyStops`, `searchStops`, `patternsThroughStop`,
  `patternStops` (devuelve `TripStop` para la alarma), `shape`.

### 6. Motor de la alarma de bajada  (`app/lib/alarm/get_off_alarm.dart`)
- **Qué hace:** decide cuándo avisar de que se acerca la parada de destino.
- **Características:**
  - Proyecta la posición GPS sobre el **trazado real** de la línea (distancia por
    carretera, no en línea recta) → evita falsos avisos en curvas y autopista.
  - Cuenta **paradas restantes** y **metros restantes**; estima **ETA** con
    velocidad suavizada (media móvil exponencial).
  - Disparo configurable: **N paradas antes / X metros antes / X minutos antes**.
  - Detección de llegada (<40 m). No repite el aviso. Ignora retrocesos por ruido GPS.
  - **Funciona sin conexión** (solo GPS + datos locales).
- **Tests:** `app/test/get_off_alarm_test.dart` — 2 tests, ambos pasan.

### 7. Esqueleto de la app  (`app/`)
- Proyecto Flutter `bajate_aqui` (Android/iOS), tema verde TITSA, Material 3.
- Pantalla de búsqueda de parada + llegadas en tiempo real con refresco manual.
- Config Android: permisos INTERNET/ubicación y excepción de tráfico HTTP solo
  para `apps.titsa.com`.
- `flutter analyze`: sin errores.

---

### 8. Alarma en segundo plano + notificaciones ✅
- **Qué hace:** sigue el viaje con la pantalla apagada o usando otra app y avisa
  al acercarse a la parada de destino. **APK de debug compilado con éxito.**
- **Componentes:**
  - `lib/alarm/trip_plan.dart` — plan de viaje serializable (línea, sentido,
    paradas con distancia sobre trazado, polilínea, destino y configuración del
    aviso) con `encode()/decode()` JSON para cruzar al isolate del servicio.
  - `lib/alarm/alarm_service.dart` — `AlarmService` (init, permisos, start/stop,
    listeners) + `_TripTaskHandler`, el handler que corre en el **isolate del
    servicio en primer plano**: se suscribe al GPS (`Geolocator`, filtro 15 m),
    alimenta el motor de alarma, actualiza la **notificación persistente**
    ("Faltan N paradas · M m · ~T min"), y al dispararse lanza **vibración** y
    una **notificación de aviso** de prioridad máxima (categoría alarma,
    `fullScreenIntent`, sonido). Envía estado y evento a la UI con
    `sendDataToMain`.
  - `lib/ui/trip_setup_page.dart` — elegir parada de bajada (solo posteriores a
    la de subida) y el tipo de aviso (1–5 paradas / 1–10 min / 100–1000 m),
    pide permisos e inicia el servicio.
  - `lib/ui/tracking_page.dart` — pantalla en vivo: paradas restantes, distancia,
    ETA, aviso destacado al sonar y botón de detener.
  - Integración en `main.dart`: `initCommunicationPort` + `AlarmService.init`,
    y acceso "Alarma" desde las llegadas de una parada (elige línea → destino).
- **Mejora de precisión:** las paradas se miden **a lo largo del trazado** (no en
  línea recta) mediante `distanceAlongShape`, coherente con la proyección del GPS.
  Función compartida por el motor y el preprocesado de datos.
- **Android:** permisos (ubicación fina + segundo plano, notificaciones, wake lock,
  vibración, foreground service + tipo location, ignorar optimización de batería)
  y declaración del `ForegroundService` con `foregroundServiceType="location"`.
- **Pendiente de esta parte:** probar en dispositivo real el comportamiento con
  pantalla apagada; sonido de alarma propio (ahora usa el de notificación);
  pantalla a pantalla completa al sonar; reanudar seguimiento tras reinicio.

### 9. Actualización de datos (GTFS) + versionado ✅
- **Qué resuelve:** cómo sabe la app que el Cabildo publicó datos nuevos y cómo
  se descargan de forma segura. Detalle completo en `docs/06-actualizacion-datos.md`.
- **Detección en origen:** el CKAN del Cabildo expone `last_modified` y `size`
  (el `hash` viene vacío). `tools/check_source_update.py` los compara con
  `data/source_state.json` → `CHANGED`/`UNCHANGED` (probado: da CHANGED y luego
  UNCHANGED).
- **Construcción + manifest:** `build_gtfs_db.py` ahora también genera
  `data/manifest.json` con versión (fecha de origen), validez del calendario
  (`valid_from`/`valid_to` = MIN/MAX de `service_dates`), **SHA-256** y tamaño.
  Generado real: versión 2026-09-27, válido 20260927..20270326.
- **CI:** `.github/workflows/gtfs-update.yml` (cron diario) comprueba, reconstruye
  si cambió y publica `guaguas-<version>.sqlite` + `manifest.json` en un release.
- **App:** `lib/data/data_updater.dart` — `ensureInstalled` (copia la BD
  empaquetada la 1ª vez), `checkForUpdate` (throttling 20 h, descarga solo el
  manifest, compara versión+sha256, descarga el sqlite, **verifica tamaño+SHA-256**,
  intercambio atómico, se aplica al reiniciar), `isExpiringSoon` (fuerza
  comprobación si el calendario caduca en ≤14 días). Integrado en `main.dart`
  (comprobación en 2º plano al abrir, con aviso "Datos actualizados").
  `min_app_version` protege cambios de esquema. Config por
  `--dart-define=DATA_MANIFEST_URL=...`.
- **Pendiente de esta parte:** elegir el alojamiento definitivo (GitHub Releases
  vs CDN propio) y sustituir `HOSTING_BASE`/`DATA_MANIFEST_URL`; descarga
  incremental (delta) si el tamaño se vuelve un problema; validación automática
  del feed en el CI antes de publicar.

### 10. Consentimiento de descarga + ajustes ✅
- **Qué resuelve:** que el usuario decida si descarga la actualización con datos
  móviles o espera a WiFi, viendo el **tamaño**; y una opción manual de comprobar.
- **Alojamiento:** GitHub Releases (tag `gtfs`). `HOSTING_BASE`/`DATA_MANIFEST_URL`
  apuntan a `github.com/OWNER/REPO/releases/download/gtfs/...` (sustituir OWNER/REPO).
- **Detección de red:** `connectivity_plus`. `onUnmeteredNetwork()` (WiFi/ethernet)
  e `isOffline()`. Preferencia **"Actualizar solo por WiFi"** (por defecto ON),
  guardada en `SharedPreferences`.
- **Flujo (comprobar ≠ descargar):** `checkForUpdate` solo baja el manifest
  (bytes) y devuelve un `UpdateCheck` (disponible, tamaño en MB, si es
  incompatible, si hay WiFi). La descarga real es `downloadAndApply`.
  - Al abrir: en WiFi (o si el usuario permite datos móviles) descarga sola; con
    datos móviles + solo-WiFi → **diálogo** que muestra "Versión X · N MB",
    validez, avisa de datos móviles y ofrece **Descargar ahora / Esperar a WiFi**
    (`lib/ui/data_update_ui.dart`, con progreso modal).
- **Pantalla de ajustes** (`lib/ui/settings_page.dart`, icono ⚙ en la barra):
  versión y validez de los datos, interruptor "solo WiFi", y **"Comprobar
  actualizaciones ahora"** (forzado; si hay novedad, usa el mismo diálogo).
- **Verificado:** `flutter analyze` limpio y APK de debug compilado.

### 11. Repositorio en GitHub + CI ✅
- **Repo:** https://github.com/protesten/bajateya (público). Rama `main`.
- **Seguridad:** `config/secrets.env` (con la `idApp`) está en `.gitignore`;
  barrido confirmado sin secretos en el repo. La `idApp` nunca va al código.
- **Incluye:** la BD semilla `app/assets/guaguas.sqlite` (para funcionar offline
  al instalar) y `manifest.json` apuntando al release `gtfs` del repo.
- **CI:** workflow con `workflow_dispatch` (opción `force`) y cron diario;
  `data/source_state.json` NO versionado para que la 1ª ejecución detecte cambio
  y publique la release inicial. YAML validado.
- **Pendiente (acción del usuario):** lanzar el workflow una vez para crear la
  primera release (ver abajo).

### 12. Primera release de datos + verificación ✅
- **Release `gtfs` publicada** por el CI: `guaguas-2026-09-27.sqlite` (15.753.216 B)
  y `manifest.json`. URL: https://github.com/protesten/bajateya/releases/tag/gtfs
- **Verificado** (descarga real): el `manifest.json` remoto es correcto y el
  SHA-256 del `.sqlite` publicado coincide con el de su manifest → la app lo
  descargaría y validaría bien.
- **Corrección aplicada:** el `.sqlite` de CI y la semilla local tenían el mismo
  tamaño pero distinto hash (SQLite no es determinista byte a byte). Para evitar
  re-descargas al instalar: (1) la semilla empaquetada ahora es exactamente el
  fichero publicado; (2) la app decide "al día" por **versión**, y usa el
  **SHA-256 solo para verificar la descarga** (`data_updater.dart`).

---

## ⬜ Pendiente (siguiente)
- Mapa con paradas y trazado (MapLibre + teselas OSM, sin clave de pago).
- Favoritos locales de líneas y paradas (sin registro), exportar/importar.
- Autorefresco del tiempo real.
- Planificador A→B con transbordos (guagua + tranvía) sobre GTFS.
- Modo turista/accesible: anuncio por voz de paradas, alto contraste.
- Multidioma (ES/EN/DE/IT/FR).
- Widgets, Wear OS, compartir viaje.
- Solicitud de `idApp` propia definitiva antes de publicar (`docs/05-...`).
