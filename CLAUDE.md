# Recordame · App de recordatorios para Android (Flutter)

## Sobre el usuario
- Habla en castellano rioplatense y no es programador: explicar todo en pasos simples.
- Quiere ver los cambios antes de instalarlos (maqueta en `docs/maqueta.html`, publicada también como artifact de Claude).

## Reglas
- **Actualizaciones automáticas:** cada push a `main` compila el APK firmado en GitHub Actions y crea un release `v1.0.N` (N = número de ejecución) con el archivo `Recordame.apk`. La app, al abrirse, compara N con su número de compilación y ofrece **Actualizar / Ahora no** (`lib/features/update/`). No romper este circuito: no cambiar el nombre del APK, el formato del tag ni el repositorio sin actualizar `UpdateService`.
- **Firma:** está en los secrets `FIRMA_BASE64` y `FIRMA_CLAVE` (alias `recordame`). No cambiar el `applicationId` (`com.afelixc.recordame`) ni la firma: si cambian, el APK nuevo no se instala encima y se pierden los recordatorios.
- **Nunca** subir claves de API, la firma (`*.jks`) ni `android/key.properties`. Cada usuario carga su propia clave de API en la app y se guarda cifrada en el teléfono.
- Si cambian las tablas de la base (`lib/data/drift/database.dart`): subir `schemaVersion`, escribir la migración y correr `dart run build_runner build` (el `.g.dart` generado se sube al repositorio).
- Las pantallas usan solo `ReminderRepository`, nunca Drift directo. `SchedulingReminderRepository` programa/cancela los avisos en cada cambio.
- Notificaciones: Android muestra máximo 3 botones (Hecho + 2 opciones con `showInNotification`). Los botones con la app cerrada corren en `onBackgroundNotificationResponse` (otro isolate, abre su propia conexión a la base).
- Repetición (`lib/data/recurrence.dart`): `dueAt` es la primera vez (de ahí sale la hora). Avisos: ids `reminderId*100 + n` (n=99 para posponer), payload = id del recordatorio. Diario/semanal/anual usan la repetición nativa del plugin; mensual y días puntuales se programan uno por uno (24) y se completan al abrir la app.
- IA (`lib/features/ai/`): cada proveedor implementa `AiProvider` (HTTP directo, salida JSON con esquema). El pedido y el esquema están en `reminder_interpreter.dart`. Claude: Messages API, `anthropic-version: 2026-10-21`, `output_config.format` json_schema, effort `low`, modelo por defecto `claude-haiku-5-5` (elegido por el usuario por costo), `fallbacks: "default"` solo en los modelos que lo admiten (Opus 5/5.5, Fable 5, Sonnet 5.5). Los nombres de modelo por defecto pueden quedar viejos: el usuario elige el modelo en Configuración (lista que devuelve su cuenta).
- Configuración (`lib/core/settings.dart`): preferencias en SharedPreferences, claves en `flutter_secure_storage` (`api_key_<proveedor>`).
- Consumo de IA: cada consulta se guarda en la tabla `UsageRecords` (base versión 3) con tokens y costo estimado (`lib/features/ai/pricing.dart`, solo precios de Claude). El saldo es el que anota el usuario menos lo consumido desde entonces. Ningún proveedor permite leer el saldo real ni cargarlo con una clave común: el botón abre la página de facturación.
- Idiomas de la IA y del dictado: español (Argentina), español neutro, inglés, italiano. Los menús siguen en español.
- Nombre: "Recordame" debajo del ícono (`android:label`), "TE RECORDARÉ" arriba dentro de la app.
- Chat con IA: lo que entiende la IA se guarda enseguida (activo) y se ofrece Modificar / Cancelar. Solapas "Último recordatorio" y "Chat completo". El dictado (`lib/features/chat/dictation.dart`) no tiene límite: se reinicia solo en cada pausa hasta Enviar o Cancelar. Mientras graba muestra "Grabando 0:12" y el texto queda oculto (botón "Ver texto").
- El chat completo se guarda en el teléfono (`AppSettings.chatHistory`, clave `chat_history`, últimos 300 mensajes) y se puede borrar.
- Varios en un mensaje: la IA devuelve una lista `reminders`; se usan hasta 2 (`maxPerMessage`, el usuario pidió dos por ahora). Los completos se guardan y por el incompleto se pregunta; al responder no se repiten los ya guardados (`_alreadySaved`).
- Pedidos relativos ("en 15 minutos"): la IA devuelve `in_minutes` y la cuenta se hace en el teléfono.
- Ejemplos (`lib/features/chat/examples_sheet.dart`): botón con recuadro que abre la lista; son solo para leer, tocarlos no crea nada. Debajo, "Cargar a mano".
- Listado → Pendientes tiene filtros Pasados / Hoy / Todos (arranca en Hoy). Borrar muestra "Deshacer" 5 segundos (`persist: false`).
- En Listado → Todos, los hechos se pintan de amarillo clarito (`highlightDone`).
- Sonido de los avisos (Configuración → Notificaciones): 4 sonidos propios en `res/raw` (campanita, timbre, suave, alerta; protegidos en `keep.xml`) o uno del teléfono con el selector de Android (`MainActivity.kt`, canal `recordame/sonido`). Android no deja cambiar el sonido de un canal: cada cambio crea `recordatorios_<n>`, borra el anterior y hace `resync`. Elegido en SharedPreferences (`notif_channel`, `notif_sound_uri`, `notif_sound_name`).
- Almanaque: deslizar a la izquierda = mes siguiente, a la derecha = anterior.
- Configuración es un menú de recuadros: cada opción abre su pantalla.
- Inteligencia artificial: recuadro "Proveedor y clave" (al entrar prueba la clave sola; verde = funcionando, rojo = error; Borrar pide confirmación), recuadro "Modelo" con los recomendados como tarjetas con explicación y costo cada 100 recordatorios, y "Ayuda".
- Copia de seguridad (`lib/features/backup/backup_service.dart`, Configuración → Copia de seguridad): archivo JSON `Recordame-copia-AAAA-MM-DD.json` (recordatorios, preferencias, chat, consumo; **nunca** las claves) en la carpeta que el usuario elige con el selector de Android (Google Drive), canal `recordame/copia` en `MainActivity.kt` (crear / escribir / abrir, con permiso persistente). Se actualiza sola cada 24 h al abrir o volver a la app. Recuperar pide confirmación con tres opciones: "Sumar los de la copia" (no borra, no repite título+fecha; no toca preferencias), "Reemplazar todo" y Cancelar. El usuario NO quiso Google Cloud ni pasos de configuración. Además la copia automática de Android incluye solo `app_flutter/` y `FlutterSharedPreferences.xml` (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`), nunca el almacenamiento cifrado.
- Google Calendar (Configuración → Google Calendar, `lib/features/calendar_sync/`, maqueta `docs/maqueta-calendario.html`): usa el calendario que ya está en el teléfono (CalendarContract por el canal `recordame/calendario` en `MainActivity.kt`, permisos READ/WRITE_CALENDAR), sin Google Cloud. El usuario NO quiere un calendario aparte: elige uno de los suyos. (2) "Enviar al calendario": `CalendarSyncRepository` (entre Scheduling y Drift) crea/actualiza/borra eventos y guarda el id en `calendarEventId` (varios con coma en días puntuales); al prenderlo pregunta "Mandar también esos N / Solo lo nuevo / Cancelar". Eventos sin alarma ni descripción del usuario pisada. (3) "Traer del calendario": 30 días / 6 meses / 1 año / Todo, con casillas y "Agregar seleccionados". (4) "Traer lo nuevo automáticamente": al prender se anotan los eventos existentes (`cal_known`) y se traen solo los nuevos: al abrir/volver a la app y **con la app cerrada** (`CalendarWorker.kt` con WorkManager: aviso de cambios del calendario por content URI + cada 15 min de respaldo; arranca un FlutterEngine sin pantalla en `calendarBackground()` de `main.dart`, que avisa "listo" por `recordame/fondo`). El código de calendario de Android está en `CalendarChannel.kt` (lo usan MainActivity y el worker).
- Batería: "Evitar que el teléfono cierre la app" abre `battery_help.dart` (para qué sirve, estado verde/amarillo con `bateriaLibre`, botón al ajuste y pasos por marca). La pantalla del calendario lo ofrece si está prendido el 4 y Android puede frenar la app. Hechos: por ahora no tocan el calendario.
- Antes de subir: `flutter analyze` y `flutter test` sin errores.

## Plan por etapas
1. ✅ Proyecto base, README, .gitignore, APK automático
2. ✅ Base de datos local, formulario manual (modo gratis), listado; aviso de actualización
3. ✅ Notificaciones (programadas, después de reiniciar, botones Hecho / Posponer 15 min, 1 hora, mañana)
3b. ✅ Repetir: diario, semanal (varios días), mensual, anual, días puntuales
4. ✅ Almanaque mensual (incluye repeticiones; `lib/features/calendar/occurrences.dart`)
5. ✅ Configuración: modo, proveedor de IA (Claude, OpenAI, Gemini), clave cifrada, instructivo, idioma
6. ✅ Chat con IA (interpreta lenguaje natural → título, fecha, hora → el usuario confirma)
7. ✅ Dictado por voz
8. ✅ Pulido: ícono propio, versión en Configuración

Ideas a futuro (el usuario dijo que por ahora no): solapa "Charlar con la IA" (chat general con la misma clave y saldo), mandar el audio a la IA en vez de usar el reconocimiento de voz de Android.

Pendiente de definir con el usuario (después de probar): qué pasa en el calendario al marcar un recordatorio como hecho (dejar con ✓, borrar o no tocar; hoy no se toca).
