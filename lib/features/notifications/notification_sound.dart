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

  static Future<void> play(String? uri) async {
    try {
      await _ch.invokeMethod('probar', {'uri': uri});
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('parar');
    } catch (_) {}
  }
}
