import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

/// Un sonido para los avisos. [uri] null = el sonido de notificación del teléfono.
class SoundChoice {
  const SoundChoice(this.name, this.uri);

  final String name;
  final String? uri;
}

const _package = 'com.afelixc.recordame';

String _raw(String name) => 'android.resource://$_package/raw/$name';

/// Sonidos que vienen con Recordame (`android/app/src/main/res/raw`).
final builtInSounds = [
  const SoundChoice('Del teléfono (el de siempre)', null),
  SoundChoice('Campanita', _raw('campanita')),
  SoundChoice('Timbre', _raw('timbre')),
  SoundChoice('Suave', _raw('suave')),
  SoundChoice('Alerta', _raw('alerta')),
];

/// Selector de sonidos de Android y prueba de sonido (código en MainActivity.kt).
class SoundPicker {
  static const _ch = MethodChannel('recordame/sonido');

  /// Abre la lista de sonidos del teléfono. null si se canceló.
  static Future<SoundChoice?> pickFromPhone(String? current) async {
    final r = await _ch.invokeMapMethod<String, String>('elegir', {
      'actual': current,
    });
    if (r == null || r['uri'] == null) return null;
    return SoundChoice(r['nombre'] ?? 'Sonido elegido', r['uri']);
  }

  /// Escuchar un sonido mientras se elige.
  static Future<void> play(String? uri) async {
    try {
      await _ch.invokeMethod('probar', {'uri': uri});
    } catch (_) {}
  }

  /// "Probar": hace sonar [uri] como un aviso, con el volumen de las
  /// notificaciones ([alarm]: con el de la alarma). [loop]: lo repite hasta
  /// que pasen [millis]. Devuelve el error, si hubo.
  static Future<String?> test(
    String? uri, {
    bool alarm = false,
    int millis = 4000,
    bool loop = false,
  }) async {
    try {
      return await _ch.invokeMethod<String>('probar', {
        'uri': uri,
        'aviso': true,
        'alarma': alarm,
        'ms': millis,
        'repetir': loop,
      });
    } catch (e) {
      return '$e';
    }
  }

  /// Cuánto dura un sonido del teléfono (null si no se sabe).
  static Future<int?> duration(String uri) async {
    try {
      return await _ch.invokeMethod<int>('duracion', {'uri': uri});
    } catch (_) {
      return null;
    }
  }

  /// Volumen con el que suenan los avisos (null si no se sabe).
  static Future<SoundVolume?> volume() async {
    try {
      final v = await _ch.invokeMapMethod<String, int>('volumen');
      return v == null ? null : SoundVolume.fromMap(v);
    } catch (_) {
      return null;
    }
  }

  /// Sube el volumen de las notificaciones (o de la alarma). false si
  /// Android no deja (por ejemplo con "No molestar"): hay que ir al ajuste.
  static Future<bool> raiseVolume({bool alarm = false}) async {
    try {
      return await _ch.invokeMethod<bool>('subirVolumen', {'alarma': alarm}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Abre el ajuste de sonido del teléfono.
  static Future<void> openSoundSettings() async {
    try {
      await const AndroidIntent(action: 'android.settings.SOUND_SETTINGS')
          .launch();
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('parar');
    } catch (_) {}
  }
}

/// Volumen de las notificaciones y de la alarma del teléfono.
class SoundVolume {
  const SoundVolume({
    required this.notifications,
    required this.notificationsMax,
    required this.notificationsMuted,
    required this.alarm,
    required this.alarmMax,
    required this.ringerMode,
  });

  factory SoundVolume.fromMap(Map<String, int> m) => SoundVolume(
    notifications: m['notificaciones'] ?? 0,
    notificationsMax: m['notificacionesMax'] ?? 0,
    notificationsMuted: (m['notificacionesMudo'] ?? 0) == 1,
    alarm: m['alarma'] ?? 0,
    alarmMax: m['alarmaMax'] ?? 0,
    ringerMode: m['modo'] ?? 2,
  );

  final int notifications;
  final int notificationsMax;
  final bool notificationsMuted;
  final int alarm;
  final int alarmMax;

  /// 0 = silencio, 1 = vibrar, 2 = normal.
  final int ringerMode;

  bool get notificationsAudible =>
      ringerMode == 2 && !notificationsMuted && notifications > 0;
  bool get alarmAudible => alarm > 0;

  /// Lo que se le muestra al usuario.
  String get notificationsText => switch (ringerMode) {
    0 => 'El teléfono está en silencio: los avisos no suenan',
    1 => 'El teléfono está en vibrar: los avisos no suenan',
    _ when notificationsMuted || notifications == 0 =>
      'El volumen de las notificaciones está en cero',
    _ => 'Volumen de las notificaciones: $notifications de $notificationsMax',
  };
}
