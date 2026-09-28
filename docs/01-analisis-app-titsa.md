# Análisis completo de la app oficial de TITSA (v2.0.4)

Fuente analizada: `App-Usuarios-Titsa/com.titsa.app.android-32_arm64-v8a.xapk`
(paquete `com.titsa.app.android`, versionCode 32, minSdk 23, targetSdk 35).
Descompilada con jadx 1.5.6. El código está sin ofuscar: 121 clases propias, ~13.500 líneas útiles.

## 1. Tecnología

| Aspecto | Qué usa TITSA |
|---|---|
| Lenguaje / UI | Java nativo Android, Views + XML, Navigation Component, `BottomNavigationView` + `DrawerLayout` |
| Red | `HttpURLConnection` a mano sobre `AsyncTask` (obsoleto desde Android 11) |
| Base de datos local | Realm (librería nativa de 8,5 MB — la mitad del peso de la app) |
| Mapas | Google Maps SDK + Google Directions API (modo `walking`) |
| Push | Firebase Cloud Messaging |
| Analítica | Firebase Analytics + Crashlytics + Ad ID |
| Seguridad | `EncryptedSharedPreferences`; credenciales de la API **embebidas en el APK** cifradas con AES y la clave también embebida (seguridad por ocultación) |
| Tráfico | `usesCleartextTraffic="true"`: el tiempo real va por **HTTP sin cifrar** |

Conclusión técnica: es una app pequeña, con arquitectura antigua (AsyncTask, callbacks, sin ViewModel/corrutinas), sin modo offline real y muy dependiente de la red.

## 2. Pantallas y funciones

Menú inferior: **Inicio · Próxima guagua · Líneas · Avisos · Favoritos**
Menú lateral: ¿Cómo llegar? · Tarifas · Puntos de venta y recarga ten+ · Billete en el móvil · Atención al cliente.

| Pantalla | Qué hace | Clase |
|---|---|---|
| Próxima guagua | Buscar parada por código o mapa → llegadas en minutos | `ui/nextbus/NextBusFragment` |
| Parada | Pestañas *Llegadas* (pull-to-refresh manual), *Líneas*, *Cómo llegar* (mapa + pasos a pie con Google Directions) | `ui/stops/*` |
| Líneas | Listado y buscador; por línea: *Paradas* (itinerario, cambiar sentido), *Horario* (**es una WebView** de `titsa.com/ws/htmlHorarioLinea.php?IdLinea=N`), *Mapa* | `ui/lines/*` |
| Avisos | Noticias/incidencias publicadas por TITSA, filtrables por línea | `ui/notifications/*` |
| Favoritos | Líneas y paradas favoritas **guardadas en el servidor** asociadas a un UUID de dispositivo | `ui/favorites/*` |
| Mis alarmas | Alarma = *días de la semana + hora + línea + parada*. El **servidor** envía un push a esa hora con la llegada. **No es una alarma de bajada** | `CreateAlarmActivity` |
| Mis alertas | Incidencias de tus líneas favoritas | `FavoritesAlertsFragment` |
| Tarifas | Calculadora origen→destino en una línea: efectivo, Bono monedero, Universitario ULL, Jubilado | `ui/fares/FaresActivity` |
| Puntos de venta | Mapa de puntos de venta/recarga ten+ cercanos | `ui/pointsofsale/*` |
| Billete en el móvil | Solo abre la app **ten+móvil** (`com.metrotenerife.viamovil`) o su ficha de Play Store | `MainActivity` |
| Atención al cliente | Marca el 922 531 300 | `MainActivity` |
| ¿Cómo llegar? (menú) | Abre Google Maps en un punto fijo (28.4592, -16.2516) | `MainActivity` |

## 3. Carencias detectadas (oportunidades para nuestra app)

1. **No hay alarma de bajada.** La "alarma" existente sólo recuerda a qué hora pasa una línea en una parada, y depende de que el servidor mande un push.
2. **No hay planificador de rutas** (A→B con transbordos). "¿Cómo llegar?" sólo guía a pie hasta una parada.
3. **No hay posición de las guaguas en el mapa** (la API sólo da minutos).
4. **Tiempo real sin auto-refresco**: hay que tirar hacia abajo para actualizar.
5. **Horarios en WebView**: lentos, sin formato móvil, sin offline, no se puede filtrar por "salidas desde mi parada".
6. **Sin modo offline**: sin red no hay ni paradas ni horarios.
7. **Favoritos atados al servidor/UUID**: se pierden al reinstalar, no hay copia ni sincronización con cuenta.
8. **Sin widgets, sin accesos directos, sin Wear OS, sin Android Auto, sin notificación en curso.**
9. **Sin accesibilidad específica** (lectura de paradas por voz, alto contraste, modo "persona mayor").
10. **Sin integración de tarjeta**: no consulta saldo ten+ por NFC; el billete se delega en otra app.
11. **Sin tranvía** (Metropolitano de Tenerife) ni intermodalidad, aunque los datos GTFS del tranvía también son públicos.
12. **Sin información de accesibilidad de parada/vehículo, ocupación, ni incidencias geolocalizadas.**
13. Privacidad mejorable: Ad ID + Analytics + Crashlytics y tráfico HTTP en claro.

## 4. Modelo de datos que maneja

Ver [02-api-titsa.md](02-api-titsa.md) para los endpoints y el formato exacto.

- **Línea**: `idLinea`, `descripcion` (se muestra con 3 dígitos: `010`, `110`…).
- **Parada**: `id`, `short_description`, `long_description`, `lat`, `lng`.
- **Itinerario**: lista de paradas con `iIdParada`, `descripcionCorta`, `coordenadaUTMX/Y` (lat/lng pese al nombre), `iIdTrayecto` (sentido), `iOrdenEnTrayecto`.
- **Llegada**: `codigoParada`, `denominacion`, `linea`, `destinoLinea`, `idTrayecto`, `minutosParaLlegar`.
- **Tarifa por sección**: `intTarifaEfectivo`, `intTarifaBonoMonedero`, `intTarifaUniversitarios`, `intTarifaJubilados`.
- **Aviso**: `id`, `title`, `subtitle`, `description`, `type`, `start_at`, `lines[]`, `translations[]` (multidioma).
