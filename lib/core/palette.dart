import 'dart:convert';

import 'package:flutter/material.dart';

/// Un color fuerte con su versión de día y de noche (la de noche, más clara
/// para que se lea sobre fondo oscuro).
class StrongColor {
  const StrongColor(this.id, this.name, this.day, this.night);

  final String id;
  final String name;
  final Color day;
  final Color night;

  Color of(bool isNight) => isNight ? night : day;
}

/// Un relleno suave (tarjetas, días del almanaque): fondo + borde, de día y
/// de noche.
class SoftColor {
  const SoftColor(
    this.id,
    this.name,
    this.dayFill,
    this.dayBorder,
    this.nightFill,
    this.nightBorder,
  );

  final String id;
  final String name;
  final Color dayFill;
  final Color dayBorder;
  final Color nightFill;
  final Color nightBorder;

  Color fill(bool isNight) => isNight ? nightFill : dayFill;
  Color border(bool isNight) => isNight ? nightBorder : dayBorder;
}

/// Combinación del ícono del teléfono (libreta con campanita): [background]
/// es el fondo y [bell] la libreta. Cada una tiene su `activity-alias` en el
/// AndroidManifest y su `ic_launcher_<id>`, generados con
/// `tool/generar_iconos.py`.
class AppIcon {
  const AppIcon(this.id, this.name, this.background, this.bell);

  final String id;
  final String name;
  final Color background;
  final Color bell;
}

/// Color de la app: barra de arriba, botones y "Nuevo".
const mainColors = <StrongColor>[
  StrongColor('tinta', 'Azul tinta', Color(0xFF2B3A67), Color(0xFF8FA2E0)),
  StrongColor('verde', 'Verde', Color(0xFF2E6B4F), Color(0xFF8CCFA8)),
  StrongColor('bordo', 'Bordó', Color(0xFF7A2E3A), Color(0xFFE59AA6)),
  StrongColor('violeta', 'Violeta', Color(0xFF5B3F8C), Color(0xFFBBA3E8)),
  StrongColor('petroleo', 'Petróleo', Color(0xFF1F5F6B), Color(0xFF86C9D6)),
  StrongColor('grafito', 'Grafito', Color(0xFF3A3F4A), Color(0xFFB8BEC9)),
  StrongColor('naranja', 'Naranja', Color(0xFFB5541C), Color(0xFFF2A774)),
];

/// El día de hoy en el almanaque.
const todayColors = <StrongColor>[
  StrongColor('ambar', 'Ámbar', Color(0xFFE8A33D), Color(0xFFF0B357)),
  StrongColor('rojo', 'Rojo', Color(0xFFD2453B), Color(0xFFF08A80)),
  StrongColor('verde', 'Verde', Color(0xFF2E9A5A), Color(0xFF7FD3A0)),
  StrongColor('azul', 'Azul', Color(0xFF2F6FE0), Color(0xFF8FB2F5)),
  StrongColor('violeta', 'Violeta', Color(0xFF7A4FD0), Color(0xFFC0A6F2)),
  StrongColor('rosa', 'Rosa', Color(0xFFD64F8A), Color(0xFFF29AC0)),
];

/// Rellenos: días con recordatorios y tarjetas de Listado → Todos.
const softColors = <SoftColor>[
  SoftColor(
    'azul',
    'Azul',
    Color(0xFFE3EBFF),
    Color(0xFF8FA2E0),
    Color(0xFF26314F),
    Color(0xFF5D74C2),
  ),
  SoftColor(
    'celeste',
    'Celeste',
    Color(0xFFDDF4FA),
    Color(0xFF7CC7DB),
    Color(0xFF1E3A44),
    Color(0xFF4C9BB0),
  ),
  SoftColor(
    'verde',
    'Verde',
    Color(0xFFE2F5E4),
    Color(0xFF86C38E),
    Color(0xFF203827),
    Color(0xFF5A9B64),
  ),
  SoftColor(
    'amarillo',
    'Amarillo',
    Color(0xFFFFF4D6),
    Color(0xFFE8C77A),
    Color(0xFF3A3320),
    Color(0xFFA88A43),
  ),
  SoftColor(
    'naranja',
    'Naranja',
    Color(0xFFFFE8D6),
    Color(0xFFF0A868),
    Color(0xFF3F2A1C),
    Color(0xFFC07A3C),
  ),
  SoftColor(
    'rosa',
    'Rosa',
    Color(0xFFFCE4EC),
    Color(0xFFE8A0B8),
    Color(0xFF3D2230),
    Color(0xFFB5698A),
  ),
  SoftColor(
    'violeta',
    'Violeta',
    Color(0xFFEDE4FB),
    Color(0xFFB49BE0),
    Color(0xFF2E2545),
    Color(0xFF8169B5),
  ),
  SoftColor(
    'gris',
    'Gris',
    Color(0xFFEEEEEE),
    Color(0xFFBDBDBD),
    Color(0xFF2A2D35),
    Color(0xFF6B7080),
  ),
  SoftColor(
    'blanco',
    'Blanco',
    Color(0xFFFFFFFF),
    Color(0xFFD5D8E0),
    Color(0xFF1F2333),
    Color(0xFF4A5068),
  ),
];

const appIcons = <AppIcon>[
  AppIcon('clasico', 'Clásico', Color(0xFF2C3A66), Color(0xFFE9A21F)),
  AppIcon('rojo', 'Rojo', Color(0xFFC62828), Color(0xFFFFFFFF)),
  AppIcon('naranja', 'Naranja', Color(0xFFE8A33D), Color(0xFF2B3A67)),
  AppIcon('verde', 'Verde', Color(0xFF2E6B4F), Color(0xFFF5D76E)),
  AppIcon('violeta', 'Violeta', Color(0xFF5B3F8C), Color(0xFFF6B7D2)),
  AppIcon('negro', 'Negro', Color(0xFF1C1C1E), Color(0xFFE0B84F)),
  AppIcon('blanco', 'Blanco', Color(0xFFFFFFFF), Color(0xFF2B3A67)),
  AppIcon('celeste', 'Celeste', Color(0xFF3FA7D6), Color(0xFFFFFFFF)),
];

T _find<T>(List<T> list, String id, String Function(T) idOf) =>
    list.firstWhere((c) => idOf(c) == id, orElse: () => list.first);

StrongColor mainColor(String id) => _find(mainColors, id, (c) => c.id);
StrongColor todayColor(String id) => _find(todayColors, id, (c) => c.id);
SoftColor softColor(String id) => _find(softColors, id, (c) => c.id);
AppIcon appIcon(String id) => _find(appIcons, id, (c) => c.id);

/// Fondos sutiles. "normal" es el de siempre (blanco de día, azul oscuro de
/// noche); los demás son apenas teñidos.
const backgroundColors = <StrongColor>[
  StrongColor('normal', 'Normal', Colors.white, Color(0xFF181D31)),
  StrongColor('cremita', 'Cremita', Color(0xFFFBF5E8), Color(0xFF1E1A14)),
  StrongColor('perla', 'Gris perla', Color(0xFFF4F5F7), Color(0xFF1C1D21)),
  StrongColor('celeste', 'Celeste', Color(0xFFEEF5FB), Color(0xFF14202B)),
  StrongColor('verde', 'Verde agua', Color(0xFFEEF7F1), Color(0xFF15201B)),
  StrongColor('rosa', 'Rosa', Color(0xFFFBF0F2), Color(0xFF221519)),
  StrongColor('lavanda', 'Lavanda', Color(0xFFF3F1FA), Color(0xFF1C1828)),
];

StrongColor backgroundColor(String id) =>
    _find(backgroundColors, id, (c) => c.id);

/// Día / noche: como el teléfono, siempre día o siempre noche.
enum DayNight { auto, day, night }

/// Los colores elegidos para un modo (día o noche).
class ColorSet {
  const ColorSet({
    this.background = 'normal',
    this.main = 'tinta',
    this.today = 'ambar',
    this.withReminders = 'azul',
    this.selected = 'tinta',
    this.pending = 'azul',
    this.done = 'amarillo',
    this.notePending = 'blanco',
    this.noteDone = 'verde',
  });

  /// Fondo (id de `backgroundColors`).
  final String background;
  final String main;
  final String today;
  final String withReminders;
  final String selected;
  final String pending;
  final String done;

  /// Libreta: las notas que faltan y las hechas.
  final String notePending;
  final String noteDone;

  ColorSet copyWith({
    String? background,
    String? main,
    String? today,
    String? withReminders,
    String? selected,
    String? pending,
    String? done,
    String? notePending,
    String? noteDone,
  }) => ColorSet(
    background: background ?? this.background,
    main: main ?? this.main,
    today: today ?? this.today,
    withReminders: withReminders ?? this.withReminders,
    selected: selected ?? this.selected,
    pending: pending ?? this.pending,
    done: done ?? this.done,
    notePending: notePending ?? this.notePending,
    noteDone: noteDone ?? this.noteDone,
  );

  String encode() => jsonEncode({
    'fondo': background,
    'app': main,
    'hoy': today,
    'dias': withReminders,
    'elegido': selected,
    'pendientes': pending,
    'hechos': done,
    'libreta_pend': notePending,
    'libreta_hechos': noteDone,
  });

  static ColorSet decode(String? text) {
    const d = ColorSet();
    if (text == null) return d;
    try {
      final j = jsonDecode(text) as Map;
      String s(String k, String def) => j[k] is String ? j[k] as String : def;
      return ColorSet(
        // Antes era sí/no (cremita o normal).
        background: j['fondo'] == true ? 'cremita' : s('fondo', d.background),
        main: s('app', d.main),
        today: s('hoy', d.today),
        withReminders: s('dias', d.withReminders),
        selected: s('elegido', d.selected),
        pending: s('pendientes', d.pending),
        done: s('hechos', d.done),
        notePending: s('libreta_pend', d.notePending),
        noteDone: s('libreta_hechos', d.noteDone),
      );
    } catch (_) {
      return d;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ColorSet && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
