import 'package:flutter/material.dart';

/// Colores de la app: azul tinta con detalles en ámbar.
class AppTheme {
  static const _brand = Color(0xFF2B3A67);
  static const _accent = Color(0xFFE8A33D);

  static ThemeData get light => _build(
    ColorScheme.fromSeed(
      seedColor: _brand,
      primary: _brand,
      secondary: _accent,
      surface: Colors.white,
    ),
  );

  static ThemeData get dark => _build(
    ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.dark,
      primary: const Color(0xFF8FA2E0),
      secondary: const Color(0xFFF0B357),
      surface: const Color(0xFF181D31),
    ),
  );

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
