# Propuesta: nuestra app

## Nombre
"GuaguasTenerife" es descriptivo pero genérico (y hay apps casi homónimas). Alternativas con gancho:

- **Bájate Aquí** — dice exactamente lo que nos diferencia (la alarma de bajada).
- **GuaguAviso**
- **Mi Parada TF**
- **ParadaYa**

Recomendación: **Bájate Aquí** (subtítulo en tiendas: "Guaguas y tranvía de Tenerife"). Evitar "TITSA" en el nombre y en el icono: no somos la app oficial.

## Arquitectura de datos

```
datos.tenerife.es (GTFS TITSA + tranvía, CC-BY)
        │  tarea semanal (GitHub Action / script)
        ▼
  gtfs.sqlite comprimido (paradas, líneas, patrones de parada, horarios, trazados simplificados)
        │  descarga en la app si hay versión nueva
        ▼
  App (100 % offline para mapa, paradas, líneas, horarios, planificador y alarma de bajada)
        │
        └── tiempo real: apps.titsa.com/apps/apps_sae_llegadas_parada.asp?idApp=<NUESTRA>&idParada=N
            (idealmente a través de un proxy pequeño nuestro para ocultar la clave, cachear 20-30 s y pasar a HTTPS)
```

- Sin backend obligatorio para el MVP: favoritos y alarmas se guardan en el móvil.
- El GTFS pesa 20 MB comprimido, pero `stop_times` se reduce muchísimo agrupando expediciones por *patrón de paradas* + hora de salida. Objetivo: < 5 MB en la app.

## Alarma de bajada — diseño

Objetivo: poder ir leyendo, dormido o sin conocer la zona y que el móvil avise a tiempo.

1. **Elegir destino**: desde una parada, una línea, el mapa, o buscando por nombre. Opcional: "estoy en la guagua de la línea X" (o detección automática).
2. **Seguimiento en segundo plano**: servicio en primer plano (Android) / Live Activity + región de geovalla (iOS) con notificación persistente: *"Línea 110 → Parada 1234 · faltan 5 paradas · ~12 min"*.
3. **Cálculo de cercanía** sobre el trazado GTFS (no en línea recta, que falla en carreteras con curvas y autopista):
   - proyectar la posición GPS sobre el `shape` de la línea → distancia restante por carretera;
   - contar paradas restantes con el orden del itinerario;
   - ETA con la velocidad media reciente, afinada con el tiempo real de TITSA en la parada destino.
4. **Disparo configurable**: N paradas antes (por defecto 2), o X metros, o X minutos. Pre-aviso suave + alarma fuerte (sonido que salta el modo silencio opcional, vibración, reloj).
5. **Ahorro de batería**: GPS de baja frecuencia cuando quedan muchas paradas; alta precisión sólo en la recta final. Geovalla del sistema como red de seguridad si el SO mata el servicio.
6. **Sin red también funciona** (GPS + GTFS local).
7. Extras: anuncio por voz de cada parada ("Próxima parada: La Cuesta"), modo acompañante (compartir el viaje por enlace con un familiar), aviso de transbordo.

## Stack técnico recomendado

- **Flutter** (ya lo tienes instalado): una base de código para Android e iOS.
  - `drift`/`sqflite` para el GTFS local, `maplibre_gl` (mapas gratuitos con teselas OSM) en lugar de Google Maps para no depender de una clave de pago.
  - `geolocator` + servicio en primer plano (`flutter_foreground_task`) para la alarma; `flutter_local_notifications`.
  - Riverpod para estado.
- Alternativa si priorizamos sólo Android y la máxima fiabilidad en segundo plano: **Kotlin + Jetpack Compose** nativo.
- Script de preprocesado GTFS → SQLite en Python, ejecutado por CI semanalmente.

## Hoja de ruta

| Fase | Contenido |
|---|---|
| 0. Preparación | Pedir `idApp` a TITSA (o permiso formal). Script GTFS→SQLite. Maquetas de pantallas |
| 1. MVP | Mapa de paradas, buscador, llegadas en tiempo real (o teóricas), líneas con itinerario y horarios nativos, favoritos locales, **alarma de bajada** |
| 2. | Planificador A→B con transbordos (guagua + tranvía), widgets, incidencias por línea, multidioma |
| 3. | Modo turista/accesible con voz, Wear OS, compartir viaje, calculadora de tarifas |
| 4. | Ocupación crowdsourcing, posición estimada de guaguas, estudio NFC ten+ |

## Aspectos legales
- GTFS del Cabildo: licencia CC-BY → citar "Fuente: TITSA / Cabildo de Tenerife (datos.tenerife.es)" en la app.
- Tiempo real: usar sólo con clave propia o autorización de TITSA.
- No usar el nombre/logo de TITSA como si fuera oficial; indicar "app no oficial".
- Privacidad: la ubicación se procesa en el móvil; sin anuncios ni Ad ID en el MVP.
