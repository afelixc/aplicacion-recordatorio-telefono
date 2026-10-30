# Recordame

App de recordatorios para Android. Le decís o le escribís en lenguaje natural lo que querés recordar ("Recordame el viernes a las 9 de la mañana lavar el auto") y arma el recordatorio con título, fecha y hora para que lo confirmes.

Se instala directamente con un APK, sin Play Store.

> **Estado:** primera versión completa. Funcionan la carga manual, el chat con IA, el dictado por voz, los recordatorios que se repiten, las notificaciones, el listado y el almanaque.

## Funciones

| Función | Estado |
|---|---|
| Pestañas: Chat, Almanaque, Listado, Configuración | ✅ |
| Carga manual de recordatorios (modo gratis, sin internet) | ✅ |
| Listado con editar, borrar y marcar como hecho | ✅ |
| Repetir: todos los días, semanas (eligiendo días), meses, años o días puntuales | ✅ |
| Aviso de versión nueva con botón para actualizar | ✅ |
| Notificaciones con botones "Hecho" y "Posponer" (15 min, 1 hora, mañana) | ✅ |
| Almanaque mensual (con las repeticiones) | ✅ |
| Configuración, clave de API cifrada e instructivo | ✅ |
| Modo IA: Claude, OpenAI o Gemini | ✅ |
| Dictado por voz | ✅ |
| Sincronizar con Google Calendar y copia en Google Drive | 🔜 Segunda etapa |

## Instalar la app en el teléfono

1. Desde el teléfono, entrá a **[Releases](https://github.com/afelixc/aplicacion-recordatorio-telefono/releases/latest)** y descargá **`Recordame.apk`**.
2. Abrí el APK en el teléfono. Android te va a pedir permiso para **instalar apps de origen desconocido**: aceptá solo para este archivo.
3. La primera vez que abras la app, aceptá el permiso de **notificaciones** y el de **alarmas y recordatorios**.
4. Recomendado: en Ajustes del teléfono → Batería, poné Recordame como **"Sin restricciones"**. Algunas marcas (Xiaomi, Samsung, Motorola, Huawei) cierran las apps en segundo plano y eso puede atrasar los avisos.

## Recordatorios que se repiten

Al cargar un recordatorio, en **Repetir** podés elegir:

- **No se repite** (una sola vez)
- **Todos los días**
- **Todas las semanas**, marcando los días (por ejemplo lunes, miércoles y viernes)
- **Todos los meses**, el mismo día (si el mes es más corto, el último día del mes)
- **Todos los años**, la misma fecha
- **Días puntuales**: elegís varias fechas sueltas

En uno que se repite, **Hecho** solo da por hecha esa vez: sigue avisando las próximas. **Posponer** agrega un aviso extra sin mover las próximas. Para que deje de repetirse, tildalo en el Listado.

## Notificaciones

Cada recordatorio avisa con una notificación a la fecha y hora indicadas, aunque la app esté cerrada y aunque se haya reiniciado el teléfono. No usan internet ni gastan saldo.

- Botones de la notificación: **Hecho**, **15 min** y **1 hora**. Android permite como máximo tres botones.
- Si tocás la notificación se abre la app con todas las opciones: **Hecho**, **15 min**, **1 hora** y **Mañana**.
- Las opciones de posponer están en `lib/features/notifications/snooze_options.dart`: para sumar una, se agrega a la lista.

## Actualizaciones

Cada vez que se publica una versión nueva, al abrir la app aparece el aviso **"Hay una versión nueva"** con dos botones: **Actualizar** o **Ahora no**. Si tocás Actualizar, la app baja la versión nueva y abre la ventana de Android para instalarla. Los recordatorios no se pierden.

La primera vez, Android te va a pedir permiso para que Recordame **instale apps**: aceptalo.

## Cargar tu clave de API (solo para el modo IA)

El **modo gratis** no necesita clave: cargás título, día y hora con un formulario.

Para el **modo IA** cada persona usa su propia clave y paga su propio consumo (cada recordatorio cuesta una fracción de centavo):

1. En la app, entrá a **Configuración**, elegí **Con IA** y, en **Inteligencia artificial**, el proveedor: Claude (Anthropic), OpenAI (ChatGPT) o Gemini (Google).
2. Abrí el instructivo **"Cómo conseguir tu clave"**: te explica cómo crear la cuenta, cargar saldo y generar la clave en ese proveedor.
3. Pegá la clave y tocá **Guardar y probar**. Probar la clave no gasta saldo.
4. En **Modelo** podés elegir qué modelo usar. Al probar la clave aparecen todos los de tu cuenta.

Después, en la pestaña **Chat**, escribí o tocá el micrófono y decí, por ejemplo: *"Recordame el viernes a las 9 de la mañana lavar el auto"* o *"Todos los lunes y jueves a las 19 ir al gimnasio"*. La IA arma el recordatorio y te lo muestra para que lo confirmes o lo corrijas antes de guardarlo. Si le falta algo (por ejemplo la hora), te pregunta.

El dictado usa el reconocimiento de voz de Android, en el idioma elegido en Configuración.

La clave se guarda **cifrada y solo en tu teléfono**. No se sube a ningún lado salvo al proveedor que elegiste, cuando le pedís que interprete un mensaje.

Las notificaciones, el listado y el almanaque funcionan sin internet y no gastan saldo.

## Compilar desde el código

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) 3.47 o superior y el SDK de Android (viene con Android Studio).

```bash
git clone https://github.com/afelixc/aplicacion-recordatorio-telefono.git
cd aplicacion-recordatorio-telefono
flutter pub get
flutter run              # con el teléfono conectado por USB o un emulador
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

No hace falta compilar a mano: cada vez que se suben cambios a `main`, GitHub Actions compila el APK, lo firma y lo publica en Releases como `v1.0.N`.

La firma del APK está guardada en los *secrets* del repositorio (`FIRMA_BASE64` y `FIRMA_CLAVE`). Sin ellos el APK sale con una firma de prueba, queda solo en la pestaña Actions y no se publica. Siempre tiene que ser la misma firma: si cambia, Android no deja instalar la versión nueva encima de la vieja.

Si cambiás las tablas de la base de datos, regenerá el código con `dart run build_runner build`.

## Estructura del código

```
lib/
  main.dart                 Punto de entrada
  app.dart                  Configuración general de la app
  core/                     Tema, formatos de fecha y servicios compartidos
  data/                     Recordatorios: modelo, interfaz y base de datos (Drift/SQLite)
  features/
    home/                   Barra de pestañas (para sumar una, agregala en home_shell.dart)
    ai/                     Proveedores de IA (para sumar uno: una clase nueva y agregarla en ai_providers.dart)
    chat/                   Chat con IA y dictado
    calendar/               Almanaque
    reminders/              Listado de recordatorios
    notifications/          Avisos, botones Hecho / Posponer y opciones de posponer
    settings/               Configuración e instructivo
    update/                 Aviso de versión nueva y actualización
```

## Seguridad

- En este repositorio **no hay ninguna clave de API**. El archivo `.gitignore` bloquea archivos de claves, certificados de firma y bases de datos.
- Si alguna vez subís una clave por error, **borrala en el sitio del proveedor y generá una nueva**: borrarla del repositorio no alcanza.
