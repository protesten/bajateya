# Backlog de ideas de ampliación (aportadas por varias IA sobre datos.tenerife.es)

Ideas para valorar más adelante. No implementadas todavía. Priorización orientativa.

## Funciones de usuario
- **"¿Cuándo salgo?"**: le dices la hora a la que quieres llegar y te avisa cuándo
  salir, teniendo en cuenta retrasos, transbordos e incidencias. *(Alto valor;
  requiere planificador con horarios GTFS + tiempo real.)*
- **Senderos lineales + TITSA** (el cruce de datos más potente del portal): alarma
  al llegar a la parada donde empieza el sendero y aviso de la **última guagua de
  vuelta**. Modo **"Excursiones en guagua"** dentro de la app + web en EN/DE para
  turistas; app aparte solo si hay uso recurrente. *(Muy diferenciador.)*
- **Predicción de ocupación** de zonas recreativas y de accesos a **Masca y Teno**
  (público local de fin de semana).
- **"Caza-Sol"**: compara estaciones meteorológicas para saber dónde hay sol con
  mar de nubes.
- **Movilidad para eventos** (vendible a organizadores/ayuntamientos).

## Empresas y administración (posible monetización realista a corto plazo)
- **Widget/pantalla "Cómo llegar en guagua"** para hoteles y coworkings.
- **Observatorio de puntualidad**: histórico del tiempo real (conviene **empezar a
  guardarlo cuanto antes**).
- **Monitor** que vigile si los datos del portal del Cabildo se siguen actualizando.
  *(Parcialmente cubierto por el CI de datos; ampliable a alertas.)*

## Integraciones (de más a menos encaje)
1. **Alarma de bajada en el reloj** (Wear OS / Apple Watch).
2. **Contador "faltan N paradas"** en pantalla de bloqueo y notificaciones
   (Live Activities iOS / notificación en vivo Android 14+).
3. **Widgets** y **órdenes por voz** (Siri / Google Assistant).
4. **Asistente** que entienda "Anaga el sábado sin coche" (la IA interpreta; los
   horarios y rutas salen de datos oficiales).
5. **Servidor MCP** con los datos de Tenerife.
6. **CarPlay / Android Auto**: lo último o nunca (el usuario va de pasajero).

## Notas de estrategia (de los modelos)
- **Monetización**: a corto plazo es más realista **cobrar a empresas** que una
  suscripción a usuarios (conversión típica 1–3 % → decenas/pocos cientos €/mes).
- **SenderoVivo**: mejor como **modo dentro de la app** + web multiidioma; app
  separada solo si hay uso recurrente.

## Relación con lo ya hecho / pendiente
- El **contador "faltan N paradas"** ya existe en la notificación persistente del
  seguimiento; falta la versión enriquecida (Live Activity / lock-screen).
- **Wear OS** y **widgets** ya estaban en el pendiente general (`docs/04`, `SEGUIMIENTO`).
