# Cómo obtiene los datos la app de TITSA

La app mezcla **tres orígenes**. Aquí está cada llamada tal y como aparece en el código descompilado
(`com/titsa/app/android/apirequests/*`).

## A. Web services "SAE" de TITSA — `http://apps.titsa.com/apps/`

Servicios antiguos (ASP clásico), **HTTP sin TLS**, autenticados con un parámetro `idApp` (clave de aplicación).
Es el origen del **tiempo real**, y es el mismo servicio que TITSA ofrece a desarrolladores terceros.

| Uso | Método y ruta | Parámetros | Respuesta |
|---|---|---|---|
| **Llegadas a una parada (tiempo real)** | `GET /apps/apps_sae_llegadas_parada.asp` | `idApp`, `idParada` | XML |
| Todas las líneas | `GET /apps/app_titsa/app_titsa_ws_lineas.asp` | `idApp` | JSON `{ "data": [ {idLinea, descripcion} ] }` |
| Líneas que pasan por una parada | `GET /apps/app_titsa/app_titsa_ws_lineas.asp` | `idApp`, `idParada` | JSON `{ "data": [ {iIdLinea, iIdParada, descripcion} ] }` |
| Itinerario (paradas) de una línea | `GET /apps/app_titsa/app_titsa_ws_itinerarios.asp` | `idApp`, `codigoLinea` | JSON `{ "data": [ {iIdParada, descripcionCorta, coordenadaUTMX, coordenadaUTMY, iIdTrayecto, iOrdenEnTrayecto} ] }` |
| Tarifa entre dos paradas | `GET /apps/apps_sae_seccion_tarifaria_con_tarifas_v2.asp` | `idApp`, `idLinea`, `paradaOrigen`, `ParadaDestino` | XML `<seccion>` con `intTarifaEfectivo`, `intTarifaBonoMonedero`, `intTarifaUniversitarios`, `intTarifaJubilados` |

Formato de llegadas (reconstruido del parser):

```xml
<llegada>
  <codigoParada>1100</codigoParada>
  <denominacion>ACORÁN</denominacion>
  <linea>14</linea>
  <destinoLinea>…</destinoLinea>
  <idTrayecto>1</idTrayecto>
  <minutosParaLlegar>7</minutosParaLlegar>
</llegada>
<!-- una <llegada> por cada guagua prevista en los próximos ~60 min -->
```

Importante: el tiempo real **sólo da minutos por parada**. No hay posición GPS de las guaguas ni identificador de vehículo.

## B. Backend propio de la app — `https://titsa-app-backend.titsa.com`

API REST (Laravel Passport, OAuth2 *password grant*) sólo para funciones de la app oficial.

Flujo de arranque:
1. `POST /api/user/registerOAuth` `{user_id:"3", uuid}` → devuelve `client_data {id, secret}`.
2. `POST /oauth/token` `{client_id, client_secret, grant_type:"password", username, password, app_version_code, platform}` → `access_token` + `refresh_token`.
   El usuario y contraseña **están embebidos en el APK** cifrados con AES (clave también embebida).
3. `POST /api/users` `{uuid, platform, version, token(FCM), language}` → crea el "usuario" del dispositivo.

Endpoints (todos con `Authorization: Bearer …`):

| Método | Ruta | Uso |
|---|---|---|
| GET | `/api/user` | Comprobar token |
| POST | `/api/users/{uuid}` | Actualizar versión / token FCM / idioma |
| GET | `/api/stops?lat=&lng=&radius=` | Paradas cercanas |
| GET | `/api/stops/{id}` | Detalle de parada |
| GET | `/api/pointofsales?lat=&lng=&radius=` | Puntos de venta cercanos |
| GET | `/api/notifications` · `/api/notifications/{id}` | Avisos/incidencias |
| GET | `/api/lines/{id}/notifications` | Avisos de una línea |
| GET/POST/DELETE | `/api/users/{uuid}/lines[/{id}]` | Líneas favoritas |
| GET/POST/DELETE | `/api/users/{uuid}/stops[/{id}]` | Paradas favoritas |
| GET/POST/DELETE | `/api/users/{uuid}/alarms[/{alarm_id}]` | Alarmas `{alarm_id, line_id, stop_id, stop_description, dias, hora}` |
| GET | `/api/users/{uuid}/notifications` | Alertas de líneas favoritas |

Push FCM: payload con `notification_id` → aviso; con `stop_id`, `stop_name`, `line_id` → alarma.

## C. Otros

- Horarios: WebView `https://titsa.com/ws/htmlHorarioLinea.php?IdLinea={id}`.
- Rutas a pie: Google Directions API con la clave de Google de TITSA.

## ⚠️ Qué debemos (y qué no) reutilizar

- **No reutilizar** las credenciales OAuth, la clave `idApp` ni la clave de Google Maps que van dentro del APK de TITSA. Son de TITSA; usarlas en otra app vulnera sus condiciones y pueden revocarlas en cualquier momento, rompiendo nuestra app. No las he descifrado ni las incluyo aquí.
- **Sí podemos usar legítimamente:**
  1. **GTFS oficial (licencia CC-BY)** del portal de datos abiertos del Cabildo:
     `https://datos.tenerife.es/ckan/dataset/36c2e26f-0d18-4b5a-b214-1636168e0765/resource/9f291323-8b78-453a-9008-4f0e3bfb3ce3/download/fichero-zip-de-google-transit.zip`
     Descargado y comprobado el 28-09-2026: 181 líneas, 3.897 paradas, 51.219 expediciones, 854 trazados (`shapes.txt`), calendario del 27-09-2026 al 26-03-2027. Los `stop_id` coinciden con los códigos de parada de TITSA (p. ej. 1100 ACORÁN). Incluye `route_color`.
  2. **GTFS del tranvía** (Metropolitano de Tenerife) en el mismo portal.
  3. **Tiempo real**: pedir a TITSA **nuestra propia `idApp`** para el servicio `apps_sae_llegadas_parada.asp` (el parámetro `idApp` existe precisamente para identificar a cada aplicación cliente; apps no oficiales como GuaguApp o GuaguaYa! muestran tiempo real de TITSA, así que hay precedente — hay que confirmarlo con TITSA). Mientras llega, la app funciona con horarios teóricos del GTFS.
- Con el GTFS podemos **sustituir por completo** el backend de TITSA para paradas, líneas, itinerarios, mapas y horarios, y además **funcionar sin conexión**.
