# Instalar y probar "Bájate Aquí" (Android)

APK de prueba: `dist/BajateAqui-0.1.0.apk` (universal, ~29 MB, todas las CPU).
Firmado con clave de depuración (vale para instalar tú mismo, no para tiendas).
**No lo compartas:** lleva la `idApp` de desarrollo de TITSA embebida.

## 1) Instalar
1. Pasa el APK al móvil (cable, Drive, Telegram a ti mismo…) o descárgalo desde
   la tarjeta de archivo que te envié.
2. Ábrelo con el explorador de archivos. Android pedirá permiso para "instalar
   apps de origen desconocido": actívalo para esa app y continúa.
3. Si aparece "Play Protect ha bloqueado": pulsa "Instalar de todos modos".

## 2) Dejar la alarma fiable (IMPORTANTE)
Abre la app → icono de ajustes (⚙) arriba a la derecha → **"Fiabilidad de la
alarma"** y deja las tres en verde:
- **Notificaciones**: Permitir.
- **Ubicación "siempre"**: Ajustar → concede "Permitir siempre" y "Ubicación
  precisa" (en Android 11+ quizá tengas que entrar a los ajustes de la app y
  elegir "Permitir todo el tiempo").
- **Sin restricción de batería**: Permitir.
- Lee el **consejo de tu fabricante** que aparece abajo (Xiaomi, Samsung, etc.)
  y activa el "Inicio automático" / "actividad en segundo plano" que indique.
  Esto es lo que evita que el móvil mate la alarma con la pantalla apagada.

## 3) Probar el tiempo real (sin moverte)
- Pantalla principal → busca una parada (p. ej. escribe "INTERCAMBIADOR" o el
  nombre de tu parada) → tócala → deberías ver las **llegadas en minutos**.
  (Si no hay llegadas ahora, prueba una parada céntrica en hora de servicio.)

## 4) Probar la alarma de bajada (prueba real)
1. En una parada, pulsa **"Alarma"** (o desde el **Mapa**, toca una parada →
   "Crear alarma de bajada").
2. Elige la **línea/sentido** que vas a coger y la **parada de destino**.
3. Elige cuándo avisar (p. ej. **2 paradas antes**) → **Iniciar alarma**.
4. Verás la pantalla de seguimiento con el **mapa del trayecto**, la parada de
   destino en rojo y tu posición en azul, y "faltan N paradas".
5. Sube a la guagua y **bloquea el móvil**. Cuando te acerques a tu parada debe
   **vibrar y sonar** con la notificación "¡Prepárate para bajar!".

### Consejo para la primera prueba
Hazla en un trayecto que ya conozcas, sin depender de ella para bajarte (lleva
la parada controlada). Así compruebas si suena a tiempo sin riesgo.

## 5) Qué mirar / posibles fallos
- **No suena con la pantalla apagada** → vuelve a "Fiabilidad de la alarma";
  casi siempre es el ahorro de batería/autoarranque del fabricante.
- **La cuenta de paradas se queda "incierta"** → puede ser sentido equivocado o
  poca cobertura GPS; la app lo avisa.
- **No aparecen llegadas** → el servicio SAE puede no tener datos para esa parada
  a esa hora; prueba otra parada/hora.

## Notas
- Los horarios y paradas funcionan **sin conexión**; el tiempo real necesita red.
- App **no oficial**. Datos: TITSA / Cabildo de Tenerife.
