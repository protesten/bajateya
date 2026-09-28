# Revisión multi-modelo (Fusion: Opus + Gemini + Codex) — 2026-09-28

Panel paralelo (opus nativo, gemini vía agy CLI, codex vía codex CLI), juez y síntesis por Opus. Generado con /reasoning.

# Evaluación técnica y de producto — "Bájate Aquí"

## Veredicto en una frase

Tienes una **fontanería excelente** (pipeline de datos, CI, arquitectura offline) construida alrededor de una **promesa central todavía sin validar**: que la alarma suene de forma fiable en un móvil real, con la pantalla apagada, en cualquier fabricante y también en iOS. La siguiente fase NO debe ser añadir funciones, sino **endurecer y demostrar la fiabilidad de la alarma como una propiedad medible**, y cerrar los bloqueantes legales de publicación. Todo lo demás es secundario a esto.

---

## 1) Lo ya construido

### Puntos fuertes (bien resueltos, con criterio)

- **Arquitectura de datos, de nivel notable-alto.** Comprimir GTFS por patrones (51.219 trips → 3.962 patrones) y simplificar trazados con Douglas-Peucker (774k → 134k puntos) para una SQLite de ~16 MB con funcionamiento 100% offline es la decisión correcta y demuestra oficio. Cero latencia de consulta, cero backend propio que mantener.
- **Pipeline CI/CD de datos, de libro.** CKAN diff → rebuild → SHA-256 + validez de calendario → GitHub Releases + manifest → descarga solo del manifest → consentimiento por tamaño (WiFi vs datos) → verificación de hash → swap atómico al reiniciar → `min_app_version` para esquema. Es auditable, reproducible, de coste operativo casi nulo (GitHub Releases como CDN) y superior a la media de apps no oficiales. El forzado de comprobación por caducidad de calendario es un detalle maduro.
- **La decisión técnica clave de la alarma es la acertada.** Proyectar el GPS sobre el **trazado real** (distancia recorrida a lo largo de la polilínea, no euclídea) es imprescindible en la orografía de Tenerife (Anaga, Teno, TF-1/TF-5 con curvas y desniveles): la distancia en línea recta subestima y dispararía tarde. EMA de velocidad, umbral de llegada (<40 m), no repetición e ignorar retrocesos por ruido son las mitigaciones correctas. **Tener tests unitarios que pasan sobre este núcleo es lo más valioso del proyecto.**
- **Ejecución en segundo plano bien elegida (para Android).** `flutter_foreground_task` en isolate propio con notificación persistente es la única forma realista de sobrevivir a Doze con la pantalla apagada. Separar datos estáticos (GTFS) de tiempo real (SAE) evita atribuir al SAE capacidades que no tiene.
- **Higiene de secretos y verificación end-to-end.** `--dart-define`, clave fuera del repo público, `flutter analyze` limpio, tiempo real probado contra el servidor real, release descargada y hash verificado. Rigor poco común.
- **Privacidad on-device como ventaja competitiva real.** El matching se hace en local sin telemetría; el impacto RGPD es mínimo por diseño.

### Debilidades y riesgos (por orden de gravedad)

**A. LA ALARMA NO ESTÁ VALIDADA EN HARDWARE REAL — este es EL riesgo del producto, por encima de todo lo demás.** Es la función estrella y la única parte no probada donde más cosas fallan en la práctica. El riesgo es **asimétrico**: que no suene es catastrófico (te pasas la parada, justo lo que la app promete evitar); que suene un poco antes es molesto pero benigno. Todo el diseño debe sesgarse a **avisar de más, nunca de menos**.

**B. OEM killers — invalida la promesa en gran parte del parque Android canario.** Xiaomi (MIUI/HyperOS), Huawei, Samsung, Oppo/OnePlus congelan servicios en primer plano si el usuario no desactiva manualmente la optimización de batería y el autoarranque. En Canarias hay mucho Xiaomi/Samsung de gama media. Sin whitelisting guiado, **la alarma puede no dispararse jamás**. Necesitas: detección de fabricante, pantalla que guíe a "no optimizar batería" / autoarranque (`auto_start_flutter` o equivalente), y prueba real en al menos un Xiaomi y un Samsung.

**C. iOS es un problema de ingeniería distinto y no resuelto.** Todo el diseño suena Android-first. iOS **no permite foreground services equivalentes**; el background location es otro modelo (region monitoring, significant-change, "always"). La alarma fiable en iOS probablemente requiera **geofencing nativo por regiones (CLRegion)** alrededor de la parada de destino como mecanismo primario, no un port del motor de polilínea. Es un track técnico separado y, por el mercado turístico (muchos iPhone), un **riesgo estratégico**, no solo técnico.

**D. Batería.** No se especifica la cadencia de muestreo. GPS de alta precisión continuo en un trayecto de 40-90 min (p. ej. 110/010 Santa Cruz–Costa Adeje) puede consumir un 8-15%. Falta **muestreo adaptativo**: p. ej. `interval=30s / precisión media` cuando faltan >5 km; escalar a `interval=3s / precisión alta` al bajar de ~1,5 km; reducir si el vehículo lleva tiempo parado; no seguir el mapa con pantalla apagada; limitar refrescos de la notificación. Sin esto, tendrás quejas de batería y el SO puede degradar tu frecuencia justo cuando la necesitas.

**E. El map matching aún puede equivocarse.** Proyectar al punto más cercano no basta cuando el trazado se auto-cruza, hace ida/vuelta por la misma vía, tiene bucles o ramales compartidos. Hay que restringir la búsqueda a una **ventana alrededor del progreso previo (progreso monótono)** e incorporar rumbo, velocidad, secuencia de observaciones y precisión GPS reportada, con un estado explícito de "posición incierta". Ojo: ignorar retrocesos protege del ruido pero puede **ocultar** un sentido mal elegido, un desvío real o que el usuario tomó otra guagua — no mantengas indefinidamente una hipótesis incorrecta.

**F. Casos límite de carretera no cubiertos:**
- **Túneles / sombra GPS** (TF-1/TF-5, viaductos, barrancos): si la última posición se congela antes del geofence y recupera señal tras rebasar la parada, la alarma no salta o salta tarde. Solución: **dead reckoning temporal** (avanzar la posición teórica según la última velocidad conocida durante un máximo de N segundos) + alarma de respaldo si se pierde GPS cerca del destino.
- **EMA de velocidad en atascos/semáforos** (accesos a Santa Cruz/La Laguna): las paradas prolongadas hunden la EMA e **inflan artificialmente el ETA**, retrasando avisos basados en tiempo. Muestra "ETA no fiable" en vez de un número engañoso y no dejes que una ETA inestable retrase una alarma que ya corresponde por distancia.
- **Variantes de itinerario / desvíos por obras o fiestas**: muchas líneas TITSA tienen expediciones parciales o variantes; si el trazado real se aleja >50 m del patrón asumido, la cuenta de paradas se desincroniza. Fallback: distancia geodésica directa al destino cuando el error de proyección supere un umbral.

**G. Los umbrales necesitan redundancia (política defensiva).** Dispara cuando se cumpla **cualquiera** de varias condiciones seguras (N paradas O X metros O X minutos), añade una **red de seguridad final por radio/geofence** al entrar cerca del destino, y avisa algo antes cuando la precisión GPS sea mala.

**H. Deuda de robustez / recuperación de estado.** ¿Qué pasa si el SO mata la app y se reabre? ¿Si se retira un permiso a mitad de trayecto? ¿Reinicio del teléfono? ¿SQLite bloqueado/corrupto mientras el servicio mantiene una lectura abierta? ¿Servicios pasada la medianoche, husos horarios y horario de verano? ¿Teléfonos sin Google Play Services? ¿Falta de espacio durante la actualización? Falta una capa explícita de **persistencia y reanudación** del estado de la alarma.

### Legal, seguridad y cumplimiento (subestimado)

**Bloqueantes de publicación — no publiques en tiendas hasta cerrarlos:**
- **Clave SAE.** El `idApp` es de desarrollo. Aunque el APK no lleve la clave, en un binario publicado el valor **termina siendo extraíble** y, con HTTP, observable en la red: asume que será público. Necesitas **autorización escrita de TITSA para distribución en producción, credencial propia y condiciones de uso** (rate limits, atribución, User-Agent). Añade caché/agrupación de consultas para no saturar el endpoint y un plan de contingencia si el SAE cae o cambia su XML.
- **Teselas OSM.** `tile.openstreetmap.org` en producción viola la política de uso de la OSMF y acabará en baneo de IP/User-Agent. Es **bloqueante**. (Ver idea prioritaria: PMTiles offline.)
- **Marca.** "App NO oficial desarrollada de forma independiente, sin vinculación con TITSA ni el Cabildo" debe ser **prominente** en ficha de tienda, onboarding/splash y about; evita logos, colores y nombres corporativos.
- **Atribución CC-BY** del GTFS al Cabildo de Tenerife: **visible en la UI**, no solo en el repo, con fuente, autor, licencia y fecha/versión de los datos (para no presentar información caducada como oficial).
- **Formularios de tienda obligatorios** (a menudo olvidados y causa de rechazo): **Data Safety** de Google Play y **Privacy Nutrition Label** de App Store. Prepara con antelación el texto de justificación de **background location** para la revisión de App Store — Apple es estricta con "location always" y lo rechaza si no argumentas bien por qué es una función principal.
- **Google Play y `fullScreenIntent`.** Play restringe cada vez más los intents de pantalla completa a alarma/llamada real; tendrás que justificarlo, y **no debes prometer pantalla completa en todos los dispositivos** ni asumir que la categoría alarma se salta "No molestar".
- **Limitación de responsabilidad** razonable: la alarma es una ayuda y no garantiza la bajada correcta.

**Seguridad:**
- **HTTP cleartext al SAE**: susceptible de MITM en WiFi público (llegadas falsas). Restringe el cleartext exclusivamente a `apps.titsa.com`, trata **toda respuesta como no confiable**, usa un parser XML seguro con límites de tamaño/tiempo/frecuencia, rechaza valores imposibles y distingue "tiempo real no disponible" de "sin llegadas".
- **Integridad ≠ autenticidad (punto infravalorado).** El SHA-256 confirma que el archivo coincide con el manifest, pero si un atacante compromete la Release **puede sustituir ambos**. Refuerzo recomendado: **firmar criptográficamente el manifest** con una clave privada cuya parte pública viaje embebida en la app, más **protección anti-downgrade**, conservación de la versión anterior para **rollback**, validación estructural/semántica antes de activar la base y comprobación de espacio libre. Y un **kill-switch remoto**: un manifest firmado que permita desactivar una base defectuosa y volver a la anterior — más importante que muchas funciones visibles.

**Privacidad (plásmala, no solo la tengas):** política clara de que "la ubicación nunca sale del dispositivo", qué se recoge, cuánto permanece, qué registran logs e informes de error (sin coordenadas, destinos ni identificadores sensibles en producción). Cualquier analítica futura: opcional, agregada, sin recorridos.

---

## 2) La propuesta / enfoque global del producto

### Fuerzas

- **Diferenciador real con dolor genuino.** La alarma de bajada resuelve algo auténtico (dormirse, no conocer la zona, turistas, viajes nocturnos, ansiedad, fatiga). Google Maps, Moovit y la app oficial **no** hacen alarma de bajada fiable y offline. Hueco de mercado real, fácil de explicar y emocionalmente reconocible.
- **Offline-first** es la decisión estratégica correcta para Canarias (roaming, zonas sin cobertura, ahorro de datos) y coherente de arriba a abajo.
- **Independencia de infraestructura ajena y coste casi cero:** la función core depende del GPS del propio móvil, no del SAE ni de servidores caros. La alarma funciona aunque el SAE caiga — hay que **explicitarlo**: la app sabe dónde vas **tú**, no dónde va la guagua.
- **Sin cuenta** reduce fricción y mejora la confianza.

### Debilidades del enfoque

- **Dependencia total de terceros que no te apoyan formalmente.** GTFS (Cabildo), SAE (TITSA), cartografía, políticas de segundo plano y tiendas. Si TITSA saca su función o te corta la clave, mueres. Mitigación: que el core funcione sin SAE (ya lo hace) y **buscar relación institucional** (ofrecer la app al Cabildo, posicionarla como herramienta de accesibilidad).
- **Riesgo de "app de una sola función".** La alarma se usa 2 minutos por trayecto. Para retención debe ser **también** buena en consulta diaria de llegadas/horarios y en activación rápida (favoritos, hábito), donde compite con apps establecidas.
- **Fricción de activación.** Línea → sentido → parada (en una lista de 40 elementos, mientras caminas o subes al bus) es difícil, sobre todo para turistas que saben dónde están y adónde van, pero no el sentido ni la expedición. Es el mayor punto de abandono.
- **La promesa "puedes dormir" eleva mucho la expectativa.** Un solo fallo en un trayecto importante destruye la confianza. El nivel de fiabilidad exigible es muy alto.
- **El mapa depende de conexión** aunque los datos de transporte sean offline: contradice la percepción de "todo offline". (Lo resuelve PMTiles.)
- **Sostenibilidad no definida (social y económica).** ¿Quién mantiene esto y su CI diario en 2 años? Nadie ha definido monetización, donaciones o patrocinio institucional. Un proyecto dependiente de una sola persona es frágil aunque sea sólido técnicamente.
- **Tranvía metropolitano**: es otro operador con feed distinto; hay que **verificar** que el mismo modelo GTFS/SAE lo cubre antes de prometer transbordos.

### Recomendación de secuenciación (primer lanzamiento con una sola promesa: "elige dónde bajas y te avisamos con antelación")

1. **Validar y endurecer la alarma en hardware real** (Android con Doze/ahorro de batería en varios fabricantes, iPhone bloqueado, túneles, usuario que sube a mitad de ruta, líneas circulares, ramales compartidos, vehículo parado, reinicio del teléfono, retirada de permisos). Define una **métrica de aceptación cuantificada**: p. ej. "aviso correcto antes del destino en ≥99% de trayectos válidos, con <0,5% de avisos prematuros graves". Apóyate en un **device farm** (Firebase Test Lab) para cobertura cross-fabricante en el CI.
2. **Cerrar bloqueantes de publicación:** clave SAE de producción autorizada por escrito, teselas PMTiles offline, política de privacidad + formularios Data Safety / Nutrition Label, disclaimer "no oficial" y atribución CC-BY visibles.
3. **Robustecer el motor:** polling adaptativo, dead reckoning en túneles, ventana de progreso monótono, fallback geodésico, política de disparo defensiva.
4. **Reducir fricción:** auto-detección de línea/sentido, y asistente de prueba + salud de alarma.
5. **Beta limitada** con telemetría voluntaria y botón "¿te avisó a tiempo?".

---

## 3) Ideas nuevas, concretas y priorizadas

### Alto valor / esfuerzo razonable (haz esto primero)

1. **Teselas vectoriales PMTiles offline (Protomaps).** Tenerife completa en teselas vectoriales OSM simplificadas ocupa **~35-50 MB**; empaquétalas o descárgalas bajo demanda y renderiza con `maplibre_gl`. Resuelve a la vez el **bloqueo legal de OSM** y el **mapa 100% offline**, eliminando la contradicción de "offline pero el mapa necesita red". Vigila el footprint total (16 MB base + ~40 MB teselas + binario) como posible fricción de instalación en gama baja: hazlas descargables, no obligatorias.

2. **"Sube y olvídate" — auto-detección de línea y sentido.** El usuario solo elige el **destino**; la app infiere la expedición cruzando su traza GPS de los primeros 2-3 min (posición, hora, paradas cercanas, movimiento >20 km/h) contra los patrones candidatos. Reduce la configuración a **un toque**, ataca la debilidad de variantes de itinerario y elimina el mayor punto de fricción. Clave: **no auto-activar si hay ambigüedad** — muestra 2-3 candidatos con nivel de confianza.

3. **Asistente de prueba de alarma pre-viaje + indicador de salud en vivo.** Antes del primer viaje, un asistente reproduce **exactamente** el sonido, vibración y notificación reales y verifica: permiso de ubicación "siempre" y precisa, notificaciones habilitadas, canal no silenciado, volumen de alarma > 0, exención de optimización de batería del fabricante, y pantalla completa permitida. Durante el trayecto, un semáforo de **salud de la alarma**: verde (GPS preciso), ámbar (precisión baja/progreso incierto), rojo (GPS perdido, permiso retirado o servicio detenido), avisando antes de que la alarma deje de ser fiable. Es puro producto: construye confianza en la función estrella y evita descubrir un problema cuando ya es tarde.

4. **Alarma escalonada con degradación elegante (doble sistema).** Preaviso suave (N+1 paradas, "prepárate") → aviso principal → aviso urgente al quedar una parada / entrar en el radio → repetición limitada hasta que el usuario confirme "estoy despierto" (nunca indefinida, con parada inmediata). Y como **red de seguridad independiente, un geofence nativo** alrededor de la parada: si el motor de polilínea falla, el geofence del SO dispara igual. En iOS, el geofence pasa a ser el mecanismo **primario**. Ataca directamente el falso negativo con dos sistemas independientes.

5. **Modo degradado explícito.** Si la posición no puede asociarse con confianza al trazado, cambia temporalmente a una **alarma geográfica conservadora** alrededor del destino y **avísalo**. Preferible una aproximación segura a fallar en silencio.

6. **Informe posviaje de un toque.** "¿Te avisamos a tiempo? — demasiado pronto / bien / tarde / no avisó". Guardado localmente, enviable de forma **voluntaria** sin recorrido completo. Es la forma de convertir la fiabilidad en evidencia y **calibrar umbrales** respetando la privacidad. Complementa con un **diagnóstico exportable** (versión de datos, modelo, permisos, precisión GPS, eventos del motor, motivo del disparo — sin coordenadas por defecto) para investigar fallos difíciles de reproducir.

7. **"Compartir estado / cuídame el viaje".** Empieza simple: mensaje preformateado a WhatsApp ("Voy en la 110 hacia Los Cristianos, parada El Camisón, llego ~18:42"). Cero infraestructura, alto valor social y viralidad. Evolución potente: notificar a un familiar cuando una **persona mayor / menor / con discapacidad** se baja en su parada. Esto **reposiciona la app como herramienta de accesibilidad/cuidado**, ayuda a la relación institucional y **justifica el background location ante App Store**. Manual, con enlace temporal que expira pronto, sin seguimiento permanente por defecto.

8. **Activación desde una parada física / destino flexible.** Al tocar una parada cercana en el mapa: "avísame al llegar a…", deduciendo las líneas posibles desde esa parada — encaja mejor con la situación real que empezar eligiendo línea. Extensión turística: elegir un **lugar/hotel/punto del mapa** y que la app sugiera las paradas de bajada convenientes (sin necesitar aún un planificador A→B completo).

### Valor medio

9. **Aviso "pulsa el botón de solicitud de parada".** Calcula los 150-250 m previos y avisa a tiempo de pulsar el botón físico — muy útil en interurbanos donde hay que solicitar parada con antelación.

10. **Detección de descenso prematuro.** Si el usuario se aleja del trazado o deja de moverse como vehículo antes del destino, pregunta si ha bajado y **libera el GPS**. Ahorra batería y evita mantener seguimiento innecesario.

11. **Detector de transbordo guagua + tranvía.** Aviso especial "llegando a intercambiador" (Santa Cruz / La Laguna) con indicación de andén/parada siguiente del Tranvía. **Requiere verificar antes** la cobertura de datos del tranvía (feed y operador distintos).

12. **"Última guagua" / aviso de fin de servicio.** "La última L015 hacia tu casa sale a las 22:47", con alarma opcional. Ataca un momento de alta ansiedad.

13. **Modos de bajo consumo y discreción.** Pantalla OLED negro total con texto rojo tenue (parada siguiente + botón de bloqueo táctil, sin toques accidentales); "solo vibración" para no molestar en el bus; háptica progresiva (impacto suave doble en la penúltima → patrón continuo tipo despertador al llegar). **Accesibilidad para personas sordas/hipoacusia**: la señal de bajada debe tener un componente **visual robusto** (pantalla + flash), no solo sonido+vibración.

14. **Alarma recurrente por contexto.** Reglas locales ("laborables, si detectas que viajo en la 014 hacia Santa Cruz, prepara destino X"), con **confirmación final** para evitar consumo accidental.

### Apuestas mayores (roadmap largo)

15. **Backend opcional de posiciones de vehículo vía GTFS-Realtime (Vehicle Positions).** Si consigues acceso del Cabildo/TITSA, la alarma pasaría de "mi GPS" a "GPS del vehículo": avisar **antes de subir**, con el móvil en el bolsillo y sin depender del GPS del usuario. Es la mejora que **cambia de categoría** el producto. Pídelo formalmente.

16. **Live Activities (iOS) / notificación en vivo (Android 14+).** Cuenta atrás de paradas en pantalla de bloqueo / isla dinámica: `[●———○] 4 paradas · ~6 min`, con cancelación rápida sin desbloquear. Alto impacto de percepción, encaja perfecto con tu notificación persistente ya existente.

---

## Resolución explícita de los tres desacuerdos del panel

- **Proxy HTTPS para el SAE (Cloudflare Worker).** Es técnicamente muy conveniente: oculta la clave, permite rotar endpoints sin actualizar el binario y controlar cuotas. **Pero introduce coste, disponibilidad, tratamiento de IP (dato personal) y nuevas responsabilidades RGPD, y trasladaría tráfico del SAE a través de tu infraestructura.** Resolución: **no es un P0 unilateral; es un paso a acordar con TITSA** en la misma conversación en la que pides la clave de producción. Mientras tanto, mitiga en cliente (cleartext restringido al host, respuestas no confiables, caché). El proxy entra cuando tengas relación formal, no antes.

- **Estrictez de iOS por ubicación.** Que el procesamiento sea on-device reduce el impacto RGPD y puede evitar el prompt de ATT (no hay tracking cross-app), **pero eso NO significa que App Store lo apruebe sin fricción**: Apple examina con lupa el uso de "location always" en background y rechaza apps que no justifiquen que es una función principal. Resolución: ambas cosas son ciertas en planos distintos — **buena posición RGPD, revisión de tienda exigente**. Prepara el texto de justificación con antelación (la función "cuídame el viaje"/accesibilidad ayuda a justificarlo).

- **Suficiencia del SHA-256.** El hash es una fortaleza para **integridad** (el archivo no se corrompió y coincide con el manifest), pero **no da autenticidad**: quien comprometa la Release puede sustituir binario y manifest a la vez. Resolución: mantén el SHA-256 y **añade firma criptográfica del manifest** (clave pública embebida), rollback y protección anti-downgrade. Es el aporte de seguridad más infravalorado del panel y debe entrar en el backlog pese a su bajo perfil de UI.

---

## Los cinco riesgos que no debes pasar por alto

1. **La fiabilidad de la alarma en background, cross-fabricante y en iOS, es el riesgo #1.** Ninguna idea de esta lista importa si la alarma no suena en un Xiaomi con la pantalla apagada. Conviértela en una **métrica medible y visible** antes de añadir nada.
2. **No publiques sin:** clave SAE de producción autorizada por escrito, teselas PMTiles de producción, política de privacidad + formularios de tienda, y disclaimer "no oficial" + atribución CC-BY prominentes.
3. **iOS necesita un diseño de background propio** (geofencing por regiones), tratado como track separado, no como port.
4. **Sesga siempre la lógica de disparo hacia avisar de más**, con red de seguridad final por geofence y modo degradado explícito.
5. **Define la sostenibilidad** (quién mantiene el proyecto y el CI, cómo se financia) y un **plan de contingencia** por si TITSA copia la función o retira la clave: mantener el core independiente del SAE es tu mejor seguro.