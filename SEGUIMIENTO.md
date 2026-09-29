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
| **Mapa (paradas + trazado del viaje)** | ✅ implementado (APK ok) |
| **Endurecimiento del motor de alarma** | ✅ (6 tests, APK ok) |
| **Fiabilidad (guía batería/OEM) + reanudación** | ✅ (APK ok) |
| **APK de prueba (release universal) + guía** | ✅ v0.1.1 |
| **Correcciones del feedback (v0.1.1)** | ✅ (APK ok) |
| **Buscador en selector de líneas + Favoritos (v0.1.2)** | ✅ (APK ok) |
| **Motor de horarios GTFS + pestaña Horario (v0.1.3)** | ✅ (APK ok) |
| **Avisar a alguien + Última guagua (v0.1.4)** | ✅ (APK ok) |
| **Fix botones seguimiento + Guía/Changelog (v0.1.5)** | ✅ (APK ok) |
| Backlog de ideas (senderos, ¿cuándo salgo?) | 📋 docs/09 |
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

### 13. Mapa (paradas + trazado del viaje) ✅
- **Tecnología:** `flutter_map` con teselas **OpenStreetMap** (sin clave de pago),
  `latlong2` para coordenadas. User-Agent propio (requisito de OSM). Atribución
  "© OpenStreetMap" visible.
- **Mapa de paradas** (`lib/ui/map_page.dart`, botón "Mapa" en la pantalla
  principal): centra en la ubicación del usuario (o Santa Cruz por defecto),
  carga las paradas del **área visible** (`GtfsDb.stopsInBounds`, solo con zoom
  ≥13 para no saturar), botón "mi ubicación", y al tocar una parada → hoja con
  "Crear alarma de bajada".
- **Mapa del viaje** en la pantalla de seguimiento (`tracking_page.dart`): dibuja
  el **trazado real** de la línea (polilínea), **resalta la parada de destino**
  (chincheta roja) y muestra la **posición en vivo** (punto azul) que ahora envía
  el servicio (`lat`/`lon` añadidos al mensaje de estado).
- **Reutilización:** selector de línea extraído a `lib/ui/alarm_entry.dart`
  (compartido por lista y mapa).
- **Verificado:** `flutter analyze` limpio, APK compilado, coordenadas de paradas
  dentro de Tenerife y servidor de teselas OSM responde (HTTP 200).
- **Pendiente producción:** el tile server público de OSM tiene política de uso
  restrictiva; para publicar conviene un proveedor de teselas propio o de pago
  (p. ej. MapTiler/Protomaps) — cambiar `osmTileUrl` en `alarm_entry.dart`.

### 14. Endurecimiento del motor de alarma ✅ (según revisión multi-modelo)
- **Fuera de ruta:** `projectOnShape` devuelve también el **desvío perpendicular**;
  si supera el umbral (150 m + precisión GPS) se marca `offRoute`, no se avanza el
  progreso (no se fía) y la UI/notificación avisan "posición incierta, ¿sentido
  correcto?". Ataca sentido equivocado / otra guagua / desvío.
- **Ventana de progreso:** la proyección se restringe a una ventana alrededor del
  progreso previo (evita saltos a tramos lejanos en trazados que se cruzan,
  circulares o con ramales compartidos). El **primer fix** localiza en todo el
  trazado (permite subir a mitad de trayecto).
- **Disparo defensivo (avisar de más):** dispara con la 1ª condición que se cumpla
  (paradas / metros / minutos) **o** por **red de seguridad geodésica** (radio de
  ~120 m al destino en línea recta), que funciona aunque el map matching falle.
- **ETA fiable:** solo se da ETA con velocidad > 0,8 m/s y ≥3 muestras (evita que
  un atasco infle el ETA y retrase un aviso por tiempo); los avisos por
  distancia/paradas no dependen del ETA.
- **Dead reckoning en túnel/sombra:** `predictWithoutFix` avanza la posición según
  la última velocidad (máx. 90 s) y dispara si la estimación alcanza el umbral;
  el servicio lo llama con un temporizador cuando el GPS lleva >12 s sin fix.
- **Muestreo GPS adaptativo (batería):** el servicio ajusta precisión/filtro por
  banda de distancia (far: medium/50 m · mid: high/20 m · near: best/5 m) y
  reinicia el stream al cambiar de banda.
- **Tests:** 6 casos y todos pasan (2 paradas antes, llegada, fuera de ruta, red
  de seguridad, subir a mitad, dead reckoning). `flutter analyze` limpio, APK ok.
- **Pendiente de esta parte (necesita hardware o publicación):** guía in-app de
  exención de batería por fabricante (OEM killers); geofencing nativo para iOS;
  persistencia/reanudación del estado tras muerte del servicio; sonido de alarma
  propio; validación real en móvil con pantalla apagada.

### 15. Fiabilidad (guía batería/OEM) + reanudación de viaje ✅
- **Guía anti "OEM killers"** (`lib/alarm/reliability.dart` + `lib/ui/reliability_page.dart`):
  detecta el fabricante con `device_info_plus` y muestra una pantalla
  "Fiabilidad de la alarma" con el estado de: notificaciones, ubicación
  "siempre", y **exención de optimización de batería**, cada uno con su botón de
  arreglo. Consejos de **autoarranque/segundo plano específicos** para
  Xiaomi/Redmi/POCO (MIUI/HyperOS), Huawei/Honor, Samsung, Oppo/Realme/OnePlus,
  vivo, y genérico. Botón para abrir los ajustes de batería.
- **Acceso:** desde Ajustes ("Fiabilidad de la alarma") y, de forma proactiva,
  al iniciar una alarma si la batería no está exenta (diálogo "revisar / empezar
  igualmente").
- **Reanudación de viaje:** el servicio marca el viaje como activo
  (`trip_active`) al iniciar y lo limpia al llegar o parar. Al abrir la app, si
  hay viaje activo pero el servicio no corre (el sistema lo mató o se cerró la
  app), se ofrece **"Reanudar"** con el plan guardado (`AlarmService.hasActiveTrip/
  savedPlan/resume`). Recupera el trayecto tras una interrupción.
- **Verificado:** `flutter analyze` limpio, APK compilado.
- **Pendiente relacionado:** geofencing nativo iOS; sonido propio; validación en
  hardware real; reanudación automática tras reinicio del teléfono (hoy es
  manual, para no sorprender al usuario).

### 16. APK de prueba + guía de instalación ✅
- **Build:** `flutter build apk --release` **universal** (arm64, armeabi-v7a, x86),
  ~29 MB (incluye la BD de 16 MB). Firmado con clave debug (suficiente para
  sideload personal). Se inyectan `TITSA_ID_APP` y `DATA_MANIFEST_URL` por
  `--dart-define`; el APK va en `dist/` (IGNORADO por git: lleva la idApp
  embebida, nunca al repo público).
- **Permiso añadido:** `USE_FULL_SCREEN_INTENT` (Android 14+ para el aviso a
  pantalla completa).
- **Entregado** al usuario para probar en su móvil; guía en
  `docs/08-instalar-y-probar.md` (instalar, dejar la alarma fiable, probar tiempo
  real y la alarma de bajada real).
- **Ahora le toca al usuario:** validar la alarma en hardware con la pantalla
  apagada (el paso que no se puede hacer desde el entorno de desarrollo).

### 17. Correcciones del primer feedback (v0.1.1) ✅
- **Líneas repetidas:** `patternsThroughStop` ahora **deduplica por línea+destino**
  (elige el patrón con más paradas por delante de la de subida). Comprobado: en el
  Intercambiador pasa de 948 patrones a 81 líneas/destino únicos. Afecta a lista y mapa.
- **Búsqueda por código de parada:** `searchStops` detecta texto numérico y busca por
  `stop_id` (exacto y por prefijo), además de por nombre. Placeholder "Buscar parada
  o código".
- **Seleccionar línea desde una parada:** cada **llegada es tocable** → crea la alarma
  de esa línea (si solo hay un destino, salta directo a configurar). Se mantiene el
  botón "Alarma".
- **Cancelar la alarma / liberar el GPS:** aviso persistente en la pantalla principal
  "Alarma activa hacia X" con **Ver** y **Detener**; y **botón "Detener" en la
  notificación** del servicio (`onNotificationButtonPressed`). Antes no había forma de
  pararla desde la app.
- **Verificado:** `flutter analyze` limpio, APK v0.1.1 compilado y entregado.

### 18. Buscador en el selector de líneas + Favoritos locales (v0.1.2) ✅
- **Buscador dentro del selector de líneas** (`lib/ui/line_chooser.dart`): hoja
  arrastrable con filtro por número/destino cuando la parada tiene muchas líneas
  (p. ej. Intercambiadores). Resuelve la mala UX de listas de 80+ líneas.
- **Favoritos de paradas** (`lib/data/favorites.dart`): guardado local en
  `SharedPreferences`, **sin registro**. Estrella ⭐ en la vista de llegadas y en
  la hoja del mapa para marcar/quitar. En la pantalla de inicio, con la búsqueda
  vacía, se muestran las **paradas favoritas** (toque → llegadas). Incluye
  exportar/importar (JSON) en el servicio (UI de import/export pendiente).
- **Verificado:** `flutter analyze` limpio, 6 tests pasan, APK v0.1.2 compilado.
- **Backlog de ideas** (varias IA sobre datos.tenerife.es) recogido en
  `docs/09-ideas-ampliacion.md`: "¿Cuándo salgo?", senderos + última guagua,
  ocupación de zonas recreativas, observatorio de puntualidad, Wear OS,
  Live Activities, asistente por voz, MCP, monetización B2B, etc.

### 19. Motor de horarios desde el GTFS (v0.1.3) ✅
- **`GtfsDb.scheduleAtStop(stopId, when)`**: próximas salidas **teóricas** por una
  parada. Calcula `trips.start_time + pattern_stops.time_offset`, filtrando por
  días de servicio (hoy y ayer, para expediciones pasada medianoche). Devuelve
  minutos, hora HH:MM, línea y destino. **Funciona sin conexión.**
- **Rendimiento:** prototipo validado contra la BD → 18 ms incluso en el mayor
  intercambiador (3.020 filas de join). Correcto vs. horario real.
- **UI:** en la pantalla de parada, **selector "Tiempo real / Horario"**. La
  pestaña Horario muestra las salidas teóricas (offline) y también permite crear
  la alarma tocando una línea. Si el SAE no responde, se sugiere el Horario.
- **Desbloquea** las ideas del backlog: "¿Cuándo salgo?", "última guagua de
  vuelta" y el modo "Excursiones en guagua" (senderos).
- **Verificado:** `flutter analyze` limpio, APK v0.1.3 compilado.
- **Idea añadida al backlog:** "Cuídame el viaje" / avisar a alguien de la
  llegada (docs/09), fase 1 sin backend (compartir por WhatsApp/SMS).

### 20. "Avisar a alguien" (Cuídame el viaje) + "Última guagua" (v0.1.4) ✅
- **Avisar a alguien** (`tracking_page.dart`, `share_plus`): botón en la pantalla
  de seguimiento que abre el compartir del sistema (WhatsApp/SMS/…) con un mensaje
  preparado ("Voy en la línea X hacia Y; te aviso al llegar", con ETA si hay). Al
  llegar cambia a "Avisar de que he llegado". Fase 1 sin backend; útil para avisar
  a familiares y **justifica el permiso de ubicación en 2º plano ante Apple**.
- **Última guagua de hoy** (`GtfsDb.lastDeparturesAtStop` + botón en la pestaña
  Horario): muestra, por línea+destino, la **última salida del día** (incluye
  expediciones pasada medianoche), marcando en rojo las que ya pasaron. Validado a
  las 22:30 contra la BD (p. ej. L50 última 00:14). Evita quedarse tirado.
- **Verificado:** `flutter analyze` limpio, APK v0.1.4 compilado.

### 21. Fix pantalla de seguimiento + Guía de usuario y Changelog (v0.1.5) ✅
- **Fix UI:** en la pantalla de seguimiento los botones se salían de pantalla.
  Ahora la info hace scroll (`SingleChildScrollView`), el mapa mide 200 px y los
  botones quedan fijos abajo en un `SafeArea` (respetan la barra de gestos).
- **Guía de usuario** (`docs/GUIA-USUARIO.md`) y **Changelog** (`CHANGELOG.md`):
  qué es la app y cómo usarla, más los cambios por versión. Canónicos y
  versionados en el repo.
- **Página web compartible** (Artifact) con la guía + novedades, para pasar a las
  personas que ayuden en las pruebas. Se actualiza en el mismo enlace cada versión.
  *(Privada: hay que compartirla desde el menú Share de la página para que otros
  la abran.)*
- **Verificado:** `flutter analyze` limpio, APK v0.1.5 compilado.

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
