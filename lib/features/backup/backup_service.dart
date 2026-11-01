import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/settings.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_repository.dart';
import '../../data/usage.dart';
import '../ai/ai_providers.dart';

/// Elegir, escribir y abrir el archivo de la copia (selector de Android:
/// Google Drive, el teléfono, etc.).
abstract class BackupFiles {
  /// Abre "Guardar como"; devuelve la dirección y el nombre del archivo, o
  /// null si se canceló.
  Future<(String uri, String name)?> create(
    String suggestedName,
    Uint8List data,
  );

  /// Sobrescribe el archivo ya elegido. false si no se pudo.
  Future<bool> write(String uri, Uint8List data);

  /// Abre el selector para elegir una copia; null si se canceló.
  Future<Uint8List?> open();
}

class AndroidBackupFiles implements BackupFiles {
  static const _channel = MethodChannel('recordame/copia');

  @override
  Future<(String, String)?> create(String suggestedName, Uint8List data) async {
    final r = await _channel.invokeMapMethod<String, String>('crear', {
      'nombre': suggestedName,
      'datos': data,
    });
    if (r == null || r['uri'] == null) return null;
    return (r['uri']!, r['nombre'] ?? suggestedName);
  }

  @override
  Future<bool> write(String uri, Uint8List data) async {
    try {
      return await _channel.invokeMethod<bool>('escribir', {
            'uri': uri,
            'datos': data,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Uint8List?> open() => _channel.invokeMethod<Uint8List>('abrir');
}

/// Lo que trae una copia, ya leído.
class BackupContents {
  const BackupContents({
    required this.createdAt,
    required this.reminders,
    required this.prefs,
    required this.chat,
    required this.usage,
  });

  final DateTime createdAt;
  final List<Reminder> reminders;
  final Map<String, String> prefs;
  final List<ChatEntry> chat;
  final List<UsageRecord> usage;
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Copia de seguridad: todos los datos de la app en un archivo JSON que el
/// usuario guarda donde quiera (por ejemplo una carpeta de Google Drive).
/// La clave de la IA no viaja nunca en la copia.
class BackupService {
  BackupService({
    required this.reminders,
    required this.usage,
    required this.settings,
    required this.files,
  });

  final ReminderRepository reminders;
  final UsageRepository usage;
  final AppSettings settings;
  final BackupFiles files;

  static const format = 'recordame-copia';
  static const autoEvery = Duration(hours: 24);

  Iterable<String> get _providerIds => aiProviders.map((p) => p.id);

  // --- Armar la copia ---

  Future<Uint8List> build({DateTime? now}) async {
    final all = await reminders.watchAll().first;
    final used = await usage.watchSince(DateTime(2000)).first;
    final data = {
      'formato': format,
      'version': 1,
      'creada': (now ?? DateTime.now()).toIso8601String(),
      'recordatorios': [for (final r in all) _reminderToJson(r)],
      'preferencias': settings.exportPrefs(_providerIds),
      'chat': [for (final e in settings.chatHistory) e.toJson()],
      'consumo': [for (final u in used) _usageToJson(u)],
    };
    // Con sangría: el "}" final queda solo al principio de un renglón, y así
    // se puede leer aunque el archivo tenga basura de una copia más larga.
    final text = '${const JsonEncoder.withIndent(' ').convert(data)}\n';
    return Uint8List.fromList(utf8.encode(text));
  }

  static String suggestedName(DateTime now) =>
      'Recordame-copia-${DateFormat('yyyy-MM-dd').format(now)}.json';

  /// Elige dónde guardar (la primera vez o para cambiarlo) y guarda.
  Future<bool> chooseAndSave() async {
    final now = DateTime.now();
    final picked = await files.create(
      suggestedName(now),
      await build(now: now),
    );
    if (picked == null) return false;
    await settings.setBackupTarget(picked.$1, picked.$2);
    await settings.setBackupResult(at: now);
    return true;
  }

  /// Guarda ahora en el archivo ya elegido.
  Future<bool> saveNow() async {
    final uri = settings.backupUri;
    if (uri == null) return false;
    final now = DateTime.now();
    final ok = await files.write(uri, await build(now: now));
    await settings.setBackupResult(
      at: ok ? now : null,
      error: ok
          ? null
          : 'No pude actualizar la copia. Puede que el archivo se haya '
                'borrado o movido: tocá "Cambiar dónde se guarda".',
    );
    return ok;
  }

  /// Copia automática: si hay un archivo elegido y pasó un día desde la última.
  Future<void> autoBackup({DateTime? now}) async {
    if (settings.backupUri == null) return;
    final last = settings.backupLast;
    now ??= DateTime.now();
    if (last != null && now.difference(last) < autoEvery) return;
    try {
      await saveNow();
    } catch (_) {
      // Sin conexión con el selector, etc.: se intenta la próxima vez.
    }
  }

  // --- Recuperar ---

  /// Elige el archivo y lo lee (todavía no cambia nada).
  Future<BackupContents?> pickAndRead() async {
    final bytes = await files.open();
    if (bytes == null) return null;
    return parse(bytes);
  }

  static BackupContents parse(Uint8List bytes) {
    final Map<String, dynamic> j;
    try {
      var text = utf8.decode(bytes, allowMalformed: true);
      final end = text.indexOf('\n}');
      if (end >= 0) text = text.substring(0, end + 2);
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException(
        'Ese archivo no es una copia de Recordame. Elegí el archivo '
        '"Recordame-copia…".',
      );
    }
    if (j['formato'] != format) {
      throw const BackupException(
        'Ese archivo no es una copia de Recordame. Elegí el archivo '
        '"Recordame-copia…".',
      );
    }
    return BackupContents(
      createdAt: DateTime.tryParse('${j['creada']}') ?? DateTime(2000),
      reminders: [
        for (final r in (j['recordatorios'] as List? ?? const []))
          if (r is Map<String, dynamic>) ?_reminderFromJson(r),
      ],
      prefs: {
        for (final e in ((j['preferencias'] as Map?) ?? const {}).entries)
          if (e.value is String) '${e.key}': e.value as String,
      },
      chat: [
        for (final e in (j['chat'] as List? ?? const []))
          if (e is Map<String, dynamic>) ?ChatEntry.fromJson(e),
      ],
      usage: [
        for (final u in (j['consumo'] as List? ?? const []))
          if (u is Map<String, dynamic>) ?_usageFromJson(u),
      ],
    );
  }

  /// Recupera la copia. Con [merge] suma los que faltan sin borrar nada
  /// (y deja las preferencias como están); si no, reemplaza todo.
  /// Devuelve cuántos recordatorios agregó.
  Future<int> restore(BackupContents c, {bool merge = false}) async {
    final current = await reminders.watchAll().first;
    if (!merge) {
      for (final r in current) {
        await reminders.delete(r.id!);
      }
    }
    String key(Reminder r) =>
        '${r.title.trim().toLowerCase()}|${r.dueAt.toIso8601String()}';
    final have = merge ? {for (final r in current) key(r)} : <String>{};
    var added = 0;
    for (final r in c.reminders) {
      if (!have.add(key(r))) continue;
      await reminders.save(r);
      added++;
    }
    // El consumo se suma sin repetir las consultas que ya estaban.
    final had = {
      for (final u in await usage.watchSince(DateTime(2000)).first)
        u.at.toIso8601String(),
    };
    for (final u in c.usage) {
      if (!had.contains(u.at.toIso8601String())) await usage.record(u);
    }
    if (!merge) await settings.importPrefs(c.prefs, c.chat, _providerIds);
    return added;
  }

  // --- Formato ---

  static String? _date(DateTime? d) => d?.toIso8601String();

  static Map<String, dynamic> _reminderToJson(Reminder r) => {
    'titulo': r.title,
    'fecha': r.dueAt.toIso8601String(),
    'repetir': r.recurrence.storageKind,
    'dias': r.recurrence.storageWeekdays,
    'fechas': r.recurrence.storageDates,
    'hecho': r.done,
    'hechoEl': _date(r.completedAt),
    'ultimaVezHecho': _date(r.lastDoneAt),
    'pospuestoHasta': _date(r.snoozedUntil),
  };

  static Reminder? _reminderFromJson(Map<String, dynamic> j) {
    final title = j['titulo'];
    final due = DateTime.tryParse('${j['fecha']}');
    if (title is! String || due == null) return null;
    DateTime? d(String k) => j[k] == null ? null : DateTime.tryParse('${j[k]}');
    return Reminder(
      title: title,
      dueAt: due,
      recurrence: Recurrence.fromStorage(
        '${j['repetir'] ?? 'none'}',
        j['dias'] is int ? j['dias'] as int : 0,
        j['fechas'] as String?,
      ),
      done: j['hecho'] == true,
      completedAt: d('hechoEl'),
      lastDoneAt: d('ultimaVezHecho'),
      snoozedUntil: d('pospuestoHasta'),
    );
  }

  static Map<String, dynamic> _usageToJson(UsageRecord u) => {
    'el': u.at.toIso8601String(),
    'proveedor': u.provider,
    'modelo': u.model,
    'entrada': u.inputTokens,
    'salida': u.outputTokens,
    'costo': u.costUsd,
  };

  static UsageRecord? _usageFromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse('${j['el']}');
    if (at == null) return null;
    return UsageRecord(
      at: at,
      provider: '${j['proveedor']}',
      model: '${j['modelo']}',
      inputTokens: (j['entrada'] as num?)?.toInt() ?? 0,
      outputTokens: (j['salida'] as num?)?.toInt() ?? 0,
      costUsd: (j['costo'] as num?)?.toDouble(),
    );
  }
}
