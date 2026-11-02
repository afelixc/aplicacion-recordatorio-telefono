import 'package:flutter/material.dart';

import 'palette.dart';

/// Colores de la app. De entrada, azul tinta con detalles en ámbar; el
/// usuario los cambia en Configuración → Colores (por separado de día y de
/// noche).
class AppTheme {
  static const _accent = Color(0xFFE8A33D);

  static ThemeData light([ColorSet colors = const ColorSet()]) {
    final main = mainColor(colors.main).day;
    return _build(
      ColorScheme.fromSeed(
        seedColor: main,
        primary: main,
        secondary: _accent,
        surface: backgroundColor(colors.background).day,
      ),
    );
  }

  static ThemeData dark([ColorSet colors = const ColorSet()]) {
    final main = mainColor(colors.main).night;
    return _build(
      ColorScheme.fromSeed(
        seedColor: main,
        brightness: Brightness.dark,
        primary: main,
        secondary: const Color(0xFFF0B357),
        surface: backgroundColor(colors.background).night,
      ),
    );
  }

  static ThemeData _build(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Los colores elegidos para el modo que se está viendo ahora (día o noche).
ColorSet currentColors(BuildContext context, ColorSet day, ColorSet night) =>
    Theme.of(context).brightness == Brightness.dark ? night : day;
