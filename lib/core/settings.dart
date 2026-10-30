import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UsageMode { free, ai }

/// Idiomas para las respuestas de la IA y el dictado por voz.
const appLanguages = <(String, String)>[
  ('es-AR', 'Español (Argentina)'),
  ('es-ES', 'Español neutro'),
];

/// Dónde se guardan las preferencias (no secretas).
abstract class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsSettingsStore implements SettingsStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

class MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Dónde se guardan las claves de API: cifradas, solo en el teléfono.
abstract class KeyStore {
  Future<String?> read(String providerId);
  Future<void> write(String providerId, String apiKey);
  Future<void> delete(String providerId);
}

class SecureKeyStore implements KeyStore {
  static const _storage = FlutterSecureStorage();
  static String _k(String id) => 'api_key_$id';

  @override
  Future<String?> read(String providerId) => _storage.read(key: _k(providerId));

  @override
  Future<void> write(String providerId, String apiKey) =>
      _storage.write(key: _k(providerId), value: apiKey);

  @override
  Future<void> delete(String providerId) =>
      _storage.delete(key: _k(providerId));
}

class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([Map<String, String>? initial]) : _keys = {...?initial};

  final Map<String, String> _keys;

  @override
  Future<String?> read(String providerId) async => _keys[providerId];

  @override
  Future<void> write(String providerId, String apiKey) async =>
      _keys[providerId] = apiKey;

  @override
  Future<void> delete(String providerId) async => _keys.remove(providerId);
}

/// Configuración de la app. Avisa a las pantallas cuando cambia.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store, this.keys);

  final SettingsStore _store;
  final KeyStore keys;

  UsageMode mode = UsageMode.free;
  String providerId = 'claude';
  String language = 'es-AR';
  final Map<String, String> _models = {};

  /// Proveedores que tienen una clave guardada.
  final Set<String> _withKey = {};

  bool hasKey(String providerId) => _withKey.contains(providerId);

  /// Modo IA con clave cargada: se puede usar el chat inteligente.
  bool get aiReady => mode == UsageMode.ai && hasKey(providerId);

  String? modelFor(String providerId) => _models[providerId];

  final Map<String, (double, DateTime)> _balances = {};

  /// Saldo que el usuario anotó que cargó y cuándo, o null.
  (double, DateTime)? balanceFor(String providerId) => _balances[providerId];

  Future<void> setBalance(String providerId, double amountUsd) async {
    final now = DateTime.now();
    _balances[providerId] = (amountUsd, now);
    notifyListeners();
    await _store.write(
      'balance_$providerId',
      '$amountUsd|${now.toIso8601String()}',
    );
  }

  Future<void> load(Iterable<String> providerIds) async {
    mode =
        UsageMode.values.asNameMap()[await _store.read('mode')] ??
        UsageMode.free;
    providerId = await _store.read('provider') ?? providerId;
    final savedLanguage = await _store.read('language');
    // Si quedó guardado un idioma que ya no se ofrece, se vuelve al de Argentina.
    if (appLanguages.any((l) => l.$1 == savedLanguage)) {
      language = savedLanguage!;
    }
    for (final id in providerIds) {
      final model = await _store.read('model_$id');
      if (model != null) _models[id] = model;
      final balance = (await _store.read('balance_$id'))?.split('|');
      if (balance != null && balance.length == 2) {
        final amount = double.tryParse(balance[0]);
        final at = DateTime.tryParse(balance[1]);
        if (amount != null && at != null) _balances[id] = (amount, at);
      }
      if ((await keys.read(id))?.isNotEmpty ?? false) _withKey.add(id);
    }
    notifyListeners();
  }

  Future<void> setMode(UsageMode value) async {
    mode = value;
    notifyListeners();
    await _store.write('mode', value.name);
  }

  Future<void> setProvider(String id) async {
    providerId = id;
    notifyListeners();
    await _store.write('provider', id);
  }

  Future<void> setLanguage(String code) async {
    language = code;
    notifyListeners();
    await _store.write('language', code);
  }

  Future<void> setModel(String providerId, String model) async {
    _models[providerId] = model;
    notifyListeners();
    await _store.write('model_$providerId', model);
  }

  Future<void> saveKey(String providerId, String apiKey) async {
    await keys.write(providerId, apiKey.trim());
    _withKey.add(providerId);
    notifyListeners();
  }

  Future<void> deleteKey(String providerId) async {
    await keys.delete(providerId);
    _withKey.remove(providerId);
    notifyListeners();
  }
}
