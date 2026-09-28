# Gestión de la actualización de datos (GTFS)

Cómo se mantiene la app al día cuando el Cabildo de Tenerife publica un GTFS nuevo.

## Principio

La app **no** descarga ni procesa el GTFS crudo (20 MB, 1,4 M de registros). Un
trabajo que controlamos nosotros lo procesa y publica una base SQLite compacta
(~16 MB) más un `manifest.json` diminuto que la app consulta.

```
Cabildo (datos.tenerife.es, CKAN)
   │  [CI diario] resource_show → ¿cambió last_modified/size?
   ▼
build_gtfs_db.py  → guaguas-<version>.sqlite  +  manifest.json (sha256, validez)
   │  publica en GitHub Releases / CDN
   ▼
App: consulta manifest.json (1×/día, WiFi) → si nuevo, descarga, verifica sha256,
     intercambio atómico → se aplica al reiniciar.
```

## Detección de cambios en origen (CKAN)

El recurso del Cabildo expone metadatos útiles vía su API:

    GET https://datos.tenerife.es/ckan/api/3/action/resource_show?id=9f291323-8b78-453a-9008-4f0e3bfb3ce3

Campos relevantes: `last_modified`, `size` (el `hash` viene **vacío**, por eso el
hash lo calculamos nosotros). `tools/check_source_update.py` compara estos dos
valores con `data/source_state.json` y responde `CHANGED`/`UNCHANGED`.

## Construcción y manifest

`tools/build_gtfs_db.py`:
- genera `guaguas.sqlite`;
- calcula el **SHA-256** y el tamaño del fichero;
- lee la **validez** del calendario (`MIN/MAX` de `service_dates`);
- consulta el `last_modified` de origen (versión);
- escribe `manifest.json`:

```json
{
  "version": "2026-09-27",
  "built_at": "2026-09-28T20:36:31+00:00",
  "source_last_modified": "2026-09-27T23:01:03.735026",
  "valid_from": "20260927",
  "valid_to": "20270326",
  "sqlite_url": ".../guaguas-2026-09-27.sqlite",
  "sqlite_sha256": "86ffb2d1…",
  "sqlite_size": 15753216,
  "min_app_version": "0.1.0"
}
```

## Automatización (CI)

`.github/workflows/gtfs-update.yml` (cron diario 05:30 UTC):
1. `check_source_update.py` → ¿cambió?
2. si sí: `build_gtfs_db.py` → sqlite + manifest.
3. publica `guaguas-<version>.sqlite` y `manifest.json` en el release `gtfs`.
4. hace commit de `source_state.json`.

El `HOSTING_BASE` apunta al release; puede cambiarse a un bucket/CDN propio.

## Lado app (`lib/data/data_updater.dart`)

- `ensureInstalled()`: primera vez, copia la BD y el manifest **empaquetados**.
- `checkForUpdate()`:
  - throttling: como mucho 1 comprobación cada 20 h (salvo `force`);
  - descarga solo el `manifest.json` (bytes) y compara `version` + `sha256`;
  - si hay novedad y `appVersion >= min_app_version`, descarga el `.sqlite`,
    **verifica tamaño y SHA-256**, y hace **intercambio atómico** (`rename`);
  - si no hay red o falla la verificación, se conserva la BD actual;
  - la BD nueva se usa en el **próximo arranque** (no se intercambia una BD abierta).
- `isExpiringSoon()`: si `valid_to` está a ≤14 días, **fuerza** la comprobación
  aunque toque throttling (evita quedarse sin horarios: el calendario actual
  caduca el 26-03-2027).
- Resultados expuestos a la UI: `upToDate`, `updated`, `skippedThrottled`,
  `offline`, `incompatible`, `failed`.

## Robustez / casos límite

- **Feed roto en origen:** como pasa por nuestro CI, podemos validar la BD antes
  de publicarla; nunca llega directamente al usuario.
- **Cambio de esquema de la BD:** `min_app_version` impide que una app vieja
  aplique una BD incompatible; le pedirá actualizar la app.
- **Descarga corrupta/parcial:** se rechaza por tamaño o SHA-256; no se aplica.
- **Sin conexión:** la app sigue funcionando con la BD instalada (100 % offline).
- **Datos caducados:** aviso al usuario y comprobación forzada al acercarse
  `valid_to`.

## Configuración en la app

La URL del manifest se inyecta en compilación:

    flutter run \
      --dart-define=TITSA_ID_APP=<idApp> \
      --dart-define=DATA_MANIFEST_URL=https://.../gtfs/manifest.json
