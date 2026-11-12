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

  /// Hace sonar [uri] desde la app. [alarm]: con el volumen de la alarma.
  /// [loop]: lo repite hasta que pasen [millis].
  static Future<void> play(
    String? uri, {
    bool alarm = false,
    int millis = 4000,
    bool loop = false,
  }) async {
    try {
      await _ch.invokeMethod('probar', {
        'uri': uri,
        'alarma': alarm,
        'ms': millis,
        'repetir': loop,
      });
    } catch (_) {}
  }

  /// Cuánto dura un sonido del teléfono (null si no se sabe).
  static Future<int?> duration(String uri) async {
    try {
      return await _ch.invokeMethod<int>('duracion', {'uri': uri});
    } catch (_) {
      return null;
    }
  }

  /// Si el volumen con el que suena un aviso está en cero (o el teléfono en
  /// vibrar / silencio). [alarm]: los que suenan aunque esté en silencio.
  static Future<bool> isMuted({bool alarm = false}) async {
    try {
      final v = await _ch.invokeMapMethod<String, int>('volumen');
      if (v == null) return false;
      if (alarm) return (v['alarma'] ?? 1) == 0;
      return (v['notificaciones'] ?? 1) == 0 || (v['modo'] ?? 2) != 2;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('parar');
    } catch (_) {}
  }
}
