# Recordame

App de recordatorios para Android. Le decís o le escribís en lenguaje natural lo que querés recordar ("Recordame el viernes a las 9 de la mañana lavar el auto") y arma el recordatorio con título, fecha y hora para que lo confirmes.

Se instala directamente con un APK, sin Play Store.

> **Estado:** en desarrollo (etapa 1 de 8). Por ahora la app muestra las cuatro pestañas vacías.
> Para ver cómo va a quedar, abrí la maqueta interactiva: [`docs/maqueta.html`](docs/maqueta.html) (descargala y abrila en el navegador).

## Funciones

| Función | Estado |
|---|---|
| Pestañas: Chat, Almanaque, Listado, Configuración | ✅ Estructura lista |
| Carga manual de recordatorios (modo gratis, sin internet) | ⏳ Etapa 2 |
| Notificaciones con botones "Hecho" y "Posponer" (15 min, 1 hora, mañana) | ⏳ Etapa 3 |
| Almanaque mensual | ⏳ Etapa 4 |
| Configuración, clave de API cifrada e instructivo | ⏳ Etapa 5 |
| Modo IA: Claude, OpenAI o Gemini | ⏳ Etapa 6 |
| Dictado por voz | ⏳ Etapa 7 |
| Sincronizar con Google Calendar y copia en Google Drive | 🔜 Segunda etapa |

## Instalar la app en el teléfono

1. Entrá a la pestaña **Releases** de este repositorio y descargá el archivo `app-release.apk` de la última versión.
   - Si todavía no hay ninguna versión publicada: entrá a **Actions**, abrí la última ejecución de "Compilar APK" que tenga ✅ y descargá `recordame-apk` (viene en un .zip; adentro está el APK).
2. Abrí el APK en el teléfono. Android te va a pedir permiso para **instalar apps de origen desconocido**: aceptá solo para este archivo.
3. La primera vez que abras la app, aceptá el permiso de **notificaciones** y el de **alarmas y recordatorios**.
4. Recomendado: en Ajustes del teléfono → Batería, poné Recordame como **"Sin restricciones"**. Algunas marcas (Xiaomi, Samsung, Motorola, Huawei) cierran las apps en segundo plano y eso puede atrasar los avisos.

## Cargar tu clave de API (solo para el modo IA)

El **modo gratis** no necesita clave: cargás título, día y hora con un formulario.

Para el **modo IA** cada persona usa su propia clave y paga su propio consumo (cada recordatorio cuesta una fracción de centavo):

1. En la app, entrá a **Configuración → Proveedor de IA** y elegí Claude, OpenAI o Gemini.
2. Abrí el instructivo **"Cómo conseguir tu clave"**: te explica cómo crear la cuenta, cargar saldo y generar la clave en ese proveedor.
3. Pegá la clave y tocá **Probar clave**.

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

No hace falta compilar a mano: cada vez que se suben cambios a `main`, GitHub Actions compila el APK solo. Para publicar una versión nueva en Releases, creá un tag que empiece con `v` (por ejemplo `v0.1.0`).

## Estructura del código

```
lib/
  main.dart                 Punto de entrada
  app.dart                  Configuración general de la app
  core/theme.dart           Colores y estilo
  features/
    home/                   Barra de pestañas (para sumar una, agregala en home_shell.dart)
    chat/                   Chat con IA y dictado
    calendar/               Almanaque
    reminders/              Listado de recordatorios
    settings/               Configuración e instructivo
```

## Seguridad

- En este repositorio **no hay ninguna clave de API**. El archivo `.gitignore` bloquea archivos de claves, certificados de firma y bases de datos.
- Si alguna vez subís una clave por error, **borrala en el sitio del proveedor y generá una nueva**: borrarla del repositorio no alcanza.
