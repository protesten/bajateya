# Bájate Aquí — Guaguas de Tenerife

App no oficial de información al viajero para TITSA, con **alarma de bajada**:
avisa cuando la guagua se acerca a tu parada de destino.

## Estructura

```
GuaguasTenerife/
├── docs/                 Análisis de la app oficial, API, competencia, propuesta y correo a TITSA
├── tools/build_gtfs_db.py  GTFS oficial (CC-BY) → base SQLite compacta para la app
├── config/               .env.example (plantilla) y secrets.env (ignorado por git; contiene la idApp)
├── data/                 gtfs.zip descargado y guaguas.sqlite generado (ignorados por git)
└── app/                  App Flutter (Android/iOS)
    ├── lib/data/titsa_realtime.dart   Cliente del SAE (tiempo real, XML)
    ├── lib/data/gtfs_db.dart          Acceso a la BD GTFS local
    ├── lib/alarm/get_off_alarm.dart   Motor de la alarma de bajada
    └── test/get_off_alarm_test.dart   Tests del motor (pasan)
```

## Fuentes de datos

- **Estático** (paradas, líneas, itinerarios, horarios, trazados): GTFS oficial del
  Cabildo de Tenerife (`datos.tenerife.es`), licencia CC-BY. La app funciona sin conexión.
- **Tiempo real**: web service SAE `apps.titsa.com/apps/apps_sae_llegadas_parada.asp`,
  con la `idApp` autorizada por TITSA (guardada en `config/secrets.env`, nunca en el código).

## Poner en marcha

1. Generar la base de datos GTFS:
   ```bash
   python tools/build_gtfs_db.py          # descarga el GTFS y genera data/guaguas.sqlite
   cp data/guaguas.sqlite app/assets/     # empaquetar en la app
   ```
2. Ejecutar la app inyectando la clave (no se incrusta en el código):
   ```bash
   cd app
   flutter run --dart-define=TITSA_ID_APP=<tu_idApp>
   ```
3. Tests del motor de alarma:
   ```bash
   cd app && flutter test
   ```

## Estado actual

- [x] Análisis completo de la app oficial y su API
- [x] Procesador GTFS → SQLite (16 MB, trazados simplificados)
- [x] Cliente de tiempo real verificado contra el SAE real
- [x] Motor de la alarma de bajada (con tests) + esqueleto Flutter (mapa/búsqueda/llegadas)
- [ ] Servicio en segundo plano + notificaciones para la alarma
- [ ] Mapa (MapLibre/OSM), favoritos locales, planificador, multidioma

Ver `docs/04-propuesta-app.md` para la hoja de ruta.

## Aviso legal
App **no oficial**. Datos: TITSA / Cabildo de Tenerife. La `idApp` es de uso autorizado
para desarrollo; se solicitará clave propia definitiva antes de publicar.
