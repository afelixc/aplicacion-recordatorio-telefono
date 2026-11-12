import 'dart:convert';

import 'priority_sounds.dart';

/// Lo que hace cada prioridad (Configuración → Notificaciones → Prioridades
/// de notificaciones). Normal avisa una vez con el sonido de la app; media y
/// alta repiten el aviso hasta que se toque "Hecho".
class PriorityConfig {
  const PriorityConfig({
    this.mediaEvery = 5,
    this.mediaFor = 480,
    this.mediaInHours = false,
    this.mediaFrom = 8,
    this.mediaTo = 22,
    this.mediaSound = 'm_campanita_doble',
    this.altaTimes = 6,
    this.altaEvery = 3,
    this.altaFor = 0,
    this.altaVibrate = true,
    this.altaFullScreen = true,
    this.altaSound = 'a_sirena',
    this.mediaPhoneUri,
    this.mediaPhoneName,
    this.altaPhoneUri,
    this.altaPhoneName,
    this.altaPhoneMillis,
  });

  /// Media: cada cuántos minutos repite.
  final int mediaEvery;

  /// Media: durante cuántos minutos (0 = todo el día).
  final int mediaFor;

  /// Media: en vez de "durante", solo entre [mediaFrom] y [mediaTo] (horas).
  final bool mediaInHours;
  final int mediaFrom;
  final int mediaTo;

  /// Media: id de [mediaSounds], o [appSound] para el de la app.
  final String mediaSound;

  /// Alta: cuántas veces suena seguido cada aviso.
  final int altaTimes;
  final int altaEvery;

  /// Alta: durante cuántos minutos (0 = hasta que toque "Hecho").
  final int altaFor;
  final bool altaVibrate;
  final bool altaFullScreen;
  final String altaSound;

  /// Sonido elegido del teléfono (cuando el sonido es [phoneSound]).
  final String? mediaPhoneUri;
  final String? mediaPhoneName;
  final String? altaPhoneUri;
  final String? altaPhoneName;

  /// Lo que dura el sonido del teléfono de la alta (para "cuántas veces").
  final int? altaPhoneMillis;

  static const appSound = 'app';
  static const phoneSound = 'tel';

  bool get mediaFromPhone => mediaSound == phoneSound && mediaPhoneUri != null;
  bool get altaFromPhone => altaSound == phoneSound && altaPhoneUri != null;

  /// Opciones de las listas.
  static const everyOptions = [3, 5, 10, 15, 30];
  static const altaEveryOptions = [1, 2, 3, 5, 10];
  static const mediaForOptions = [60, 180, 480, 0];
  static const altaForOptions = [60, 180, 480, 0];
  static const timesOptions = [3, 5, 6, 8, 10, 15];

  /// Android deja programar pocos avisos por app: cada recordatorio repite
  /// hasta esta cantidad de veces (después sigue el aviso fijo).
  static const maxRepeats = 48;

  static String forLabel(int minutes, {bool alta = false}) => switch (minutes) {
    0 => alta ? 'Hasta que toque Hecho' : 'Todo el día',
    60 => '1 hora',
    _ => '${minutes ~/ 60} horas',
  };

  PrioritySound get altaSoundInfo => altaSounds.firstWhere(
    (s) => s.id == altaSound,
    orElse: () => altaSounds.first,
  );

  String get altaSoundName =>
      altaFromPhone ? altaPhoneName ?? 'Del teléfono' : altaSoundInfo.name;

  /// Lo que dura una vez el sonido de la alta. Los del teléfono pueden ser
  /// largos: se toman hasta 20 segundos.
  int get altaMillis => altaFromPhone
      ? (altaPhoneMillis ?? 3000).clamp(1000, 20000)
      : altaSoundInfo.millis;

  /// Sonido propio de la media (si el elegido no existe, el primero).
  String get mediaSoundId => mediaSounds.any((s) => s.id == mediaSound)
      ? mediaSound
      : mediaSounds.first.id;

  String get mediaSoundName => mediaSound == appSound
      ? 'El de la app'
      : mediaFromPhone
      ? mediaPhoneName ?? 'Del teléfono'
      : mediaSounds
            .firstWhere(
              (s) => s.id == mediaSound,
              orElse: () => mediaSounds.first,
            )
            .name;

  PriorityConfig copyWith({
    int? mediaEvery,
    int? mediaFor,
    bool? mediaInHours,
    int? mediaFrom,
    int? mediaTo,
    String? mediaSound,
    int? altaTimes,
    int? altaEvery,
    int? altaFor,
    bool? altaVibrate,
    bool? altaFullScreen,
    String? altaSound,
    String? mediaPhoneUri,
    String? mediaPhoneName,
    String? altaPhoneUri,
    String? altaPhoneName,
    int? altaPhoneMillis,
  }) => PriorityConfig(
    mediaEvery: mediaEvery ?? this.mediaEvery,
    mediaFor: mediaFor ?? this.mediaFor,
    mediaInHours: mediaInHours ?? this.mediaInHours,
    mediaFrom: mediaFrom ?? this.mediaFrom,
    mediaTo: mediaTo ?? this.mediaTo,
    mediaSound: mediaSound ?? this.mediaSound,
    altaTimes: altaTimes ?? this.altaTimes,
    altaEvery: altaEvery ?? this.altaEvery,
    altaFor: altaFor ?? this.altaFor,
    altaVibrate: altaVibrate ?? this.altaVibrate,
    altaFullScreen: altaFullScreen ?? this.altaFullScreen,
    altaSound: altaSound ?? this.altaSound,
    mediaPhoneUri: mediaPhoneUri ?? this.mediaPhoneUri,
    mediaPhoneName: mediaPhoneName ?? this.mediaPhoneName,
    altaPhoneUri: altaPhoneUri ?? this.altaPhoneUri,
    altaPhoneName: altaPhoneName ?? this.altaPhoneName,
    altaPhoneMillis: altaPhoneMillis ?? this.altaPhoneMillis,
  );

  Map<String, dynamic> toJson() => {
    'mCada': mediaEvery,
    'mDurante': mediaFor,
    'mHorario': mediaInHours,
    'mDesde': mediaFrom,
    'mHasta': mediaTo,
    'mSonido': mediaSound,
    'aVeces': altaTimes,
    'aCada': altaEvery,
    'aDurante': altaFor,
    'aVibrar': altaVibrate,
    'aPantalla': altaFullScreen,
    'aSonido': altaSound,
    'mTelUri': ?mediaPhoneUri,
    'mTelNombre': ?mediaPhoneName,
    'aTelUri': ?altaPhoneUri,
    'aTelNombre': ?altaPhoneName,
    'aTelMs': ?altaPhoneMillis,
  };

  String encode() => jsonEncode(toJson());

  static PriorityConfig decode(String? raw) {
    const d = PriorityConfig();
    if (raw == null) return d;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      int i(String k, int def) => j[k] is int ? j[k] as int : def;
      bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
      String s(String k, String def) => j[k] is String ? j[k] as String : def;
      String? o(String k) => j[k] is String ? j[k] as String : null;
      return PriorityConfig(
        mediaEvery: i('mCada', d.mediaEvery),
        mediaFor: i('mDurante', d.mediaFor),
        mediaInHours: b('mHorario', d.mediaInHours),
        mediaFrom: i('mDesde', d.mediaFrom),
        mediaTo: i('mHasta', d.mediaTo),
        mediaSound: s('mSonido', d.mediaSound),
        altaTimes: i('aVeces', d.altaTimes),
        altaEvery: i('aCada', d.altaEvery),
        altaFor: i('aDurante', d.altaFor),
        altaVibrate: b('aVibrar', d.altaVibrate),
        altaFullScreen: b('aPantalla', d.altaFullScreen),
        altaSound: s('aSonido', d.altaSound),
        mediaPhoneUri: o('mTelUri'),
        mediaPhoneName: o('mTelNombre'),
        altaPhoneUri: o('aTelUri'),
        altaPhoneName: o('aTelNombre'),
        altaPhoneMillis: j['aTelMs'] is int ? j['aTelMs'] as int : null,
      );
    } catch (_) {
      return d;
    }
  }

  /// Horas en las que repite un aviso de prioridad media que tocó a las
  /// [first] (sin contar ese primer aviso).
  List<DateTime> mediaRepeats(DateTime first) {
    final every = Duration(minutes: mediaEvery);
    final DateTime end;
    var start = first.add(every);
    if (mediaInHours) {
      final day = DateTime(first.year, first.month, first.day);
      final from = day.add(Duration(hours: mediaFrom));
      end = day.add(Duration(hours: mediaTo <= mediaFrom ? 24 : mediaTo));
      while (start.isBefore(from)) {
        start = start.add(every);
      }
    } else {
      end = mediaFor == 0
          ? DateTime(first.year, first.month, first.day, 23, 59)
          : first.add(Duration(minutes: mediaFor));
    }
    return _steps(start, end, every);
  }

  /// Horas en las que vuelve a sonar un aviso de prioridad alta.
  List<DateTime> altaRepeats(DateTime first) {
    final every = Duration(minutes: altaEvery);
    final end = altaFor == 0
        ? first.add(every * maxRepeats)
        : first.add(Duration(minutes: altaFor));
    return _steps(first.add(every), end, every);
  }

  static List<DateTime> _steps(DateTime start, DateTime end, Duration every) {
    final out = <DateTime>[];
    for (
      var t = start;
      !t.isAfter(end) && out.length < maxRepeats;
      t = t.add(every)
    ) {
      out.add(t);
    }
    return out;
  }
}
