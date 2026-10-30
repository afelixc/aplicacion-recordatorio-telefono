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
- IA (`lib/features/ai/`): cada proveedor implementa `AiProvider` (HTTP directo, salida JSON con esquema). El pedido y el esquema están en `reminder_interpreter.dart`. Claude: Messages API, `anthropic-version: 2026-10-21`, `output_config.format` json_schema, effort `low`, `fallbacks: "default"` en los modelos que lo admiten. Los nombres de modelo por defecto pueden quedar viejos: el usuario elige el modelo en Configuración (lista que devuelve su cuenta).
- Configuración (`lib/core/settings.dart`): preferencias en SharedPreferences, claves en `flutter_secure_storage` (`api_key_<proveedor>`).
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
8. Pulido y versión final

Segunda etapa (no implementar todavía): Google Calendar (`calendarEventId` ya existe en la tabla) y copia en Google Drive.
