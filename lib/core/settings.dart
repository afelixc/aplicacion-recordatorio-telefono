import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UsageMode { free, ai }

/// Idiomas para las respuestas de la IA y el dictado por voz.
const appLanguages = <(String, String)>[
  ('es-AR', 'Español (Argentina)'),
  ('es-ES', 'Español neutro'),
  ('en-US', 'English'),
  ('it-IT', 'Italiano'),
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
/// Un mensaje del chat con la IA (se guarda en el teléfono).
class ChatEntry {
  const ChatEntry(
    this.text, {
    this.mine = false,
    this.error = false,
    required this.at,
  });

  final String text;
  final bool mine;
  final bool error;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    't': text,
    if (mine) 'm': true,
    if (error) 'e': true,
    'a': at.toIso8601String(),
  };

  static ChatEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = j['t'];
    final at = DateTime.tryParse('${j['a']}');
    if (text is! String || at == null) return null;
    return ChatEntry(text, mine: j['m'] == true, error: j['e'] == true, at: at);
  }
}

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

  /// Lo hablado con la IA (los últimos [maxChat] mensajes).
  final List<ChatEntry> chatHistory = [];
  static const maxChat = 300;

  Future<void> addChat(ChatEntry entry) async {
    chatHistory.add(entry);
    if (chatHistory.length > maxChat) {
      chatHistory.removeRange(0, chatHistory.length - maxChat);
    }
    await _saveChat();
  }

  Future<void> clearChat() async {
    chatHistory.clear();
    await _saveChat();
  }

  Future<void> _saveChat() => _store.write(
    'chat_history',
    jsonEncode([for (final e in chatHistory) e.toJson()]),
  );

  // --- Google Calendar (el calendario del teléfono) ---

  String? calendarId;
  String? calendarName;

  /// De Recordame → al calendario.
  bool calendarSend = false;

  /// Del calendario → a Recordame, automático.
  bool calendarAuto = false;

  /// Eventos que ya se vieron (para traer solo los nuevos).
  final Set<String> calendarKnown = {};

  Future<void> setCalendar(String id, String name) async {
    calendarId = id;
    calendarName = name;
    notifyListeners();
    await _store.write('cal_id', id);
    await _store.write('cal_name', name);
  }

  Future<void> setCalendarSend(bool value) async {
    calendarSend = value;
    notifyListeners();
    await _store.write('cal_send', '$value');
  }

  Future<void> setCalendarAuto(
    bool value, {
    Iterable<String> known = const [],
  }) async {
    calendarAuto = value;
    calendarKnown
      ..clear()
      ..addAll(known);
    notifyListeners();
    await _store.write('cal_auto', '$value');
    await _saveKnown();
  }

  Future<void> addCalendarKnown(Iterable<String> ids) async {
    calendarKnown.addAll(ids);
    await _saveKnown();
  }

  Future<void> _saveKnown() =>
      _store.write('cal_known', jsonEncode(calendarKnown.toList()));

  // --- Copia de seguridad ---

  /// Archivo elegido para la copia (dirección de Android) y su nombre.
  String? backupUri;
  String? backupName;
  DateTime? backupLast;

  /// Por qué falló la última copia automática (null si anduvo).
  String? backupError;

  Future<void> setBackupTarget(String uri, String name) async {
    backupUri = uri;
    backupName = name;
    notifyListeners();
    await _store.write('backup_uri', uri);
    await _store.write('backup_name', name);
  }

  Future<void> setBackupResult({DateTime? at, String? error}) async {
    if (at != null) backupLast = at;
    backupError = error;
    notifyListeners();
    if (at != null) await _store.write('backup_last', at.toIso8601String());
    await _store.write('backup_error', error ?? '');
  }

  /// Las preferencias que viajan en la copia (sin claves de API).
  Map<String, String> exportPrefs(Iterable<String> providerIds) => {
    'mode': mode.name,
    'provider': providerId,
    'language': language,
    for (final id in providerIds)
      if (_models[id] != null) 'model_$id': _models[id]!,
    for (final id in providerIds)
      if (_balances[id] != null)
        'balance_$id':
            '${_balances[id]!.$1}|${_balances[id]!.$2.toIso8601String()}',
  };

  /// Restaura preferencias y chat de una copia.
  Future<void> importPrefs(
    Map<String, String> prefs,
    List<ChatEntry> chat,
    Iterable<String> providerIds,
  ) async {
    for (final e in prefs.entries) {
      if (e.key == 'mode' ||
          e.key == 'provider' ||
          e.key == 'language' ||
          e.key.startsWith('model_') ||
          e.key.startsWith('balance_')) {
        await _store.write(e.key, e.value);
      }
    }
    chatHistory
      ..clear()
      ..addAll(
        chat.length > maxChat ? chat.sublist(chat.length - maxChat) : chat,
      );
    await _saveChat();
    await load(providerIds);
  }

  Future<void> load(Iterable<String> providerIds) async {
    calendarId = await _store.read('cal_id');
    calendarName = await _store.read('cal_name');
    calendarSend = await _store.read('cal_send') == 'true';
    calendarAuto = await _store.read('cal_auto') == 'true';
    try {
      calendarKnown
        ..clear()
        ..addAll(
          ((jsonDecode(await _store.read('cal_known') ?? '[]') as List)).map(
            (e) => '$e',
          ),
        );
    } catch (_) {}
    backupUri = await _store.read('backup_uri');
    backupName = await _store.read('backup_name');
    backupLast = DateTime.tryParse(await _store.read('backup_last') ?? '');
    final backupErr = await _store.read('backup_error');
    backupError = (backupErr?.isEmpty ?? true) ? null : backupErr;
    final chat = await _store.read('chat_history');
    if (chat != null) {
      try {
        chatHistory
          ..clear()
          ..addAll((jsonDecode(chat) as List).map(ChatEntry.fromJson).nonNulls);
      } catch (_) {
        // Si quedó algo roto, se empieza un chat nuevo.
      }
    }
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
