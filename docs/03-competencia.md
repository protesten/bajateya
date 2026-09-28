# Apps de otras provincias y empresas: qué tienen y qué copiar

| App | Ámbito | Funciones destacables |
|---|---|---|
| **EMT Madrid** (oficial) | Madrid urbano | **"Avísame"**: eliges la parada de bajada y el móvil vibra cuando quedan 2 paradas. Saldo de la Tarjeta Transporte Público por **NFC**. **Ocupación** del bus en rutas y paradas. Perfil con alertas de incidencias de tus líneas habituales. Planificador, esquemas de líneas, EMT + BiciMAD |
| **TMB App** (Barcelona) | Metro + bus | Tiempo real, alertas personalizadas de incidencias, **navegación accesible para personas ciegas** (avisos en parada activables), T-mobilitat en el móvil |
| **GuaguasLPA** (Guaguas Municipales, Las Palmas GC) | Urbano | Menú personalizable, "paradas en tránsito", favoritos **sin registro**, **ocupación** de la guagua, saldo de tarjeta, mapa con puntos de venta, estaciones Sítycleta y parkings |
| **Global / TGC Guaguas Global** (Gran Canaria) | Interurbano | Tiempo real por parada, consulta de saldo/recargas, calculadora de viaje |
| **Moovit** | Global | Navegación en vivo con **aviso de bajada** ("te avisamos cuando llegue tu parada"), planificador multimodal, avisos de servicio, cuánto falta para tu parada |
| **Citymapper** | Global (no Tenerife) | "**Get off**" alerts, tracking en vivo, mejor vagón/salida, notificación persistente del viaje |
| **Transit** | Global | **GO**: te avisa cuándo salir de casa, cuándo bajar y cuándo transbordar; **crowdsourcing** de la posición del vehículo desde los móviles de los viajeros (actualiza más rápido que el GPS del bus) y encuesta de ocupación de un toque |
| **Google Maps** | Global | Navegación en transporte público con notificaciones de bajada, datos GTFS de TITSA |
| **NeverMiss** y similares | Android | Alarma de bajada por GPS pensada para quien se duerme en el trayecto |
| **GuaguApp / GuaguaYa! / Guaguas de Tenerife / Tu Guagua** | Tenerife (no oficiales) | Tiempo real de TITSA, mapa de paradas, geolocalización. GuaguaYa! tiene reseñas de datos desactualizados → **lección: automatizar la actualización del GTFS** |
| **ten+móvil (Vía-Móvil)** | Tenerife (oficial) | Compra y validación de billetes de guagua y tranvía — no replicable, pero sí enlazable |

## Ideas a incorporar (priorizadas)

**Imprescindibles (lo que nos diferencia desde el día 1)**
1. **Alarma de bajada** por GPS + trazado GTFS, configurable ("avisar 1–3 paradas antes" o "X metros/minutos antes"), con vibración, sonido y aviso en el reloj. *(EMT, Moovit, Citymapper, Transit)*
2. **Funciona sin conexión**: paradas, líneas, mapa y horarios del GTFS dentro de la app.
3. **Tiempo real con auto-refresco** y notificación en curso "la 110 llega en 4 min".
4. **Favoritos locales sin registro**, con exportar/importar.

**Muy útiles**
5. Planificador A→B con transbordos (guagua + tranvía) usando GTFS.
6. Modo "turista / no conozco la zona": seguir el trayecto en el mapa, lista de paradas que quedan con la actual resaltada, **anuncio por voz** de cada parada.
7. Aviso de salida: "sal ya de casa para coger la 015".
8. Widgets y accesos directos a paradas favoritas; Wear OS; Android Auto (para acompañantes).
9. Incidencias de TITSA filtradas por mis líneas.

**Diferenciales a medio plazo**
10. Saldo de la tarjeta ten+ por NFC (requiere estudiar si la tarjeta lo permite sin claves del operador).
11. Ocupación por crowdsourcing (encuesta de un toque al subir), como Transit.
12. Posición estimada de la guagua en el mapa (interpolando horario + minutos de tiempo real, y más adelante crowdsourcing).
13. Accesibilidad: TalkBack completo, modo de letra grande/alto contraste, modo "persona mayor", guiado para personas ciegas.
14. Multidioma (ES/EN/DE/IT/FR) — Tenerife tiene muchísimo turista.
15. Calculadora de tarifas (efectivo, Bono, ULL, jubilado, residentes/gratuidad).

## Fuentes
- [EMT Madrid – Nueva app oficial (Ayto. Madrid)](https://www.madrid.es/portales/munimadrid/es/Inicio/Actualidad/Noticias/Nueva-App-oficial-de-la-EMT/?vgnextfmt=default&vgnextoid=aaba8c4e140b7410VgnVCM1000000b205a0aRCRD&vgnextchannel=a12149fa40ec9410VgnVCM100000171f5a0aRCRD)
- [Aplicaciones móviles EMT Madrid 2.0](https://www.madrid.es/portales/munimadrid/es/Inicio/El-Ayuntamiento/Movilidad-y-transportes/Transportes/Aplicaciones-Moviles-EMT-Madrid-2-0?vgnextfmt=default&vgnextoid=5e8dcf7b6ea9e410VgnVCM1000000b205a0aRCRD&vgnextchannel=6a829c133cf89010VgnVCM100000d90ca8c0RCRD)
- [TMB App – accesibilidad](https://pre.tmb.cat/es/barcelona/tmb-app-t-mobilitat/accesibilidad) · [TMB App FAQ](https://www.tmb.cat/en/barcelona/tmb-app-t-mobilitat/tmb-app-help-center/faq)
- [Guaguas Municipales – actualización de la app](https://www.guaguas.com/empresa/noticias/guaguas-municipales-lanza-la-actualizacion-para-su-aplicacion-movil-que-mejora-la-usabilidad-y-renueva-el-diseno-3385)
- [Global – App móvil](https://guaguasglobal.com/app-movil/)
- [Moovit – App Store](https://apps.apple.com/es/app/moovit-transporte-p%C3%BAblico/id498477945) · [Citymapper – App Store](https://apps.apple.com/es/app/citymapper/id469463298)
- [Transit – crowdsourcing](https://blog.transitapp.com/transit-adds-crowdsourced-real-time-in-175-cities-a90ec97685ec/) · [Transit – ocupación](https://blog.transitapp.com/public-transit-riders-are-helping-one-another-avoid-crowds-c929a4fe6c7d/)
- [App de aviso de parada final (Depor)](https://depor.com/depor-play/tecnologia/android-conoce-la-app-que-te-alerta-cada-vez-que-estas-cerca-a-tu-parada-final-del-autobus-sistema-operativo-autobus-aplicaciones-smartphone-tecnologia-truco-tutorial-nnda-nnni-noticia/)
- [GuaguaYa! – Google Play](https://play.google.com/store/apps/details?hl=en_US&id=com.makedalafela.guaguaya) · [GuaguApp](https://www.androidlista.com/item/android-apps/478023/guaguapp/) · [Tu Guagua (datos.tenerife.es)](https://datos.tenerife.es/en/reutiliza/apps-y-empresas?view=utilizacion&id=13)
- [ten+móvil – Google Play](https://play.google.com/store/apps/details?id=com.metrotenerife.viamovil&hl=en_US)
- [GTFS TITSA – datos.tenerife.es](https://datos.tenerife.es/es/datos/conjuntos-de-datos/informacion-sobre-el-sistema-de-transporte-de-titsa-en-tenerife)
