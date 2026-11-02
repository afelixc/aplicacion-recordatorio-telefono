import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/settings.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_repository.dart';

/// Elegir, leer y escribir los archivos de Gmail en Drive (selector de
/// Android). Usa el mismo canal que la copia de seguridad.
abstract class GmailFiles {
  /// Abre "Guardar como"; devuelve la dirección del archivo o null.
  Future<String?> create(String name, Uint8List data);
  Future<bool> write(String uri, Uint8List data);
  Future<Uint8List?> read(String uri);
}

class AndroidGmailFiles implements GmailFiles {
  static const _channel = MethodChannel('recordame/copia');

  @override
  Future<String?> create(String name, Uint8List data) async {
    final r = await _channel.invokeMapMethod<String, String>('crear', {
      'nombre': name,
      'datos': data,
    });
    return r?['uri'];
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
  Future<Uint8List?> read(String uri) async {
    try {
      return await _channel.invokeMethod<Uint8List>('leer', {'uri': uri});
    } on PlatformException {
      return null;
    }
  }
}

/// Recordame en la barra de Gmail de la compu, por medio de dos archivos en
/// Drive:
///
/// * `Recordame-gmail.json`: la lista completa. La escribe solo el teléfono,
///   cada vez que algo cambia.
/// * `Recordame-gmail-cambios.json`: lo que se hizo en Gmail (crear,
///   modificar, tildar, destildar, borrar). Lo escribe solo el complemento
///   de Gmail. El teléfono lo aplica y anota en la lista los cambios ya
///   aplicados (`aplicados`), así Gmail los saca de su archivo.
///
/// Cada archivo tiene un solo escritor: nunca se pisan.
class GmailSync {
  GmailSync({
    required this.reminders,
    required this.settings,
    required this.files,
  });

  final ReminderRepository reminders;
  final AppSettings settings;
  final GmailFiles files;

  static const mainName = 'Recordame-gmail.json';
  static const changesName = 'Recordame-gmail-cambios.json';
  static const mainFormat = 'recordame-gmail';
  static const changesFormat = 'recordame-gmail-cambios';

  /// Cuántos cambios ya aplicados se recuerdan (para no aplicarlos dos veces).
  static const keepApplied = 500;

  // --- Elegir dónde se guardan ---

  /// Crea los dos archivos (dos "Guardar" seguidos en la misma carpeta).
  /// Devuelve false si se canceló alguno.
  Future<bool> choose() async {
    final pair = _randomId('par');
    final main = await files.create(
      mainName,
      _encode(await _mainJson(pair: pair, applied: const [], refs: const {})),
    );
    if (main == null) return false;
    final changes = await files.create(
      changesName,
      _encode({'formato': changesFormat, 'par': pair, 'cambios': []}),
    );
    if (changes == null) return false;
    await settings.setGmailFiles(main, changes, pair);
    await settings.writeRaw('gmail_applied', '[]');
    await settings.writeRaw('gmail_refs', '{}');
    await settings.writeRaw('gmail_hash', '');
    await settings.setGmailResult(at: DateTime.now());
    return true;
  }

  Future<void> disconnect() => settings.clearGmail();

  // --- Sincronizar ---

  bool _running = false;

  /// Trae lo hecho en Gmail y deja la lista al día. Devuelve cuántos
  /// cambios llegaron de la compu, o null si no se pudo.
  Future<int?> sync({bool force = false, DateTime? now}) async {
    if (!settings.gmailOn || _running) return 0;
    _running = true;
    try {
      now ??= DateTime.now();
      // Si la revisión con la app cerrada está en eso, se espera la próxima.
      final lock = DateTime.tryParse(
        await settings.readFresh('gmail_lock') ?? '',
      );
      if (!force &&
          lock != null &&
          now.difference(lock).abs() < const Duration(seconds: 50)) {
        return 0;
      }
      await settings.writeRaw('gmail_lock', now.toIso8601String());

      final applied = _readList(await settings.readFresh('gmail_applied'));
      final refs = _readRefs(await settings.readFresh('gmail_refs'));

      var arrived = 0;
      String? error;
      final bytes = await files.read(settings.gmailChangesUri!);
      if (bytes == null) {
        error =
            'No pude leer lo que llega de Gmail. Revisá la conexión a '
            'internet, o tocá "Elegir dónde se guarda" de nuevo.';
      } else {
        final changes = _decode(bytes);
        if (changes != null &&
            changes['formato'] == changesFormat &&
            (changes['par'] == null || changes['par'] == settings.gmailPair)) {
          for (final op in (changes['cambios'] as List? ?? const [])) {
            if (op is! Map) continue;
            final id = '${op['id']}';
            if (applied.contains(id)) continue;
            try {
              await apply(op.cast<String, dynamic>(), refs);
            } catch (_) {
              // Un cambio raro no frena a los demás.
            }
            applied.add(id);
            arrived++;
          }
        }
      }
      while (applied.length > keepApplied) {
        applied.removeAt(0);
      }
      await settings.writeRaw('gmail_applied', jsonEncode(applied));
      await settings.writeRaw('gmail_refs', jsonEncode(refs));

      final ok = await _export(applied, refs, force: force || arrived > 0);
      if (!ok) {
        error ??=
            'No pude actualizar la lista en Drive. Revisá la conexión a '
            'internet, o tocá "Elegir dónde se guarda" de nuevo.';
      }
      await settings.setGmailResult(
        at: error == null ? now : null,
        error: error,
      );
      await settings.writeRaw('gmail_lock', '');
      return error == null ? arrived : null;
    } finally {
      _running = false;
    }
  }

  /// Escribe la lista si cambió algo desde la última vez.
  Future<bool> _export(
    List<String> applied,
    Map<String, int> refs, {
    bool force = false,
  }) async {
    final data = await _mainJson(
      pair: settings.gmailPair,
      applied: applied,
      refs: refs,
    );
    final content = Map.of(data)..remove('actualizado');
    final hash = _hash(jsonEncode(content));
    if (!force && hash == await settings.readFresh('gmail_hash')) return true;
    final ok = await files.write(settings.gmailMainUri!, _encode(data));
    if (ok) await settings.writeRaw('gmail_hash', hash);
    return ok;
  }

  // --- Lo que llega de Gmail ---

  static final _day = DateFormat('yyyy-MM-dd');

  /// Aplica un cambio hecho en Gmail. [refs] une los creados en la compu
  /// (`pc-…`) con su id en el teléfono.
  Future<void> apply(Map<String, dynamic> op, Map<String, int> refs) async {
    final type = op['tipo'];
    final rec = '${op['rec']}';
    if (type == 'crear') {
      if (refs.containsKey(rec)) return;
      final due = _dueFrom(op) ?? DateTime.now().add(const Duration(hours: 1));
      final title = '${op['titulo'] ?? ''}'.trim();
      final saved = await reminders.save(
        Reminder(
          title: title.isEmpty ? 'Recordatorio' : title,
          dueAt: due,
          recurrence: _recurrenceFrom(op, due, const Recurrence.none()),
        ),
      );
      refs[rec] = saved.id!;
      return;
    }
    final id = refs[rec] ?? int.tryParse(rec);
    if (id == null) return;
    final current = await reminders.getById(id);
    if (current == null) return; // ya se borró en el teléfono
    switch (type) {
      case 'modificar':
        final due = _dueFrom(op) ?? current.dueAt;
        final title = '${op['titulo'] ?? ''}'.trim();
        await reminders.save(
          current.copyWith(
            title: title.isEmpty ? current.title : title,
            dueAt: due,
            recurrence: _recurrenceFrom(op, due, current.recurrence),
            clearSnoozedUntil: true,
          ),
        );
      case 'hecho':
        if (!current.done) await reminders.setDone(id, true);
      case 'pendiente':
        if (current.done) await reminders.setDone(id, false);
      case 'borrar':
        await reminders.delete(id);
    }
  }

  static DateTime? _dueFrom(Map<String, dynamic> op) {
    final day = DateTime.tryParse('${op['fecha']}');
    if (day == null) return null;
    final hm = '${op['hora'] ?? '09:00'}'.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.tryParse(hm.first) ?? 9,
      hm.length > 1 ? int.tryParse(hm[1]) ?? 0 : 0,
    );
  }

  static Recurrence _recurrenceFrom(
    Map<String, dynamic> op,
    DateTime due,
    Recurrence current,
  ) {
    final kind = op['repetir'];
    if (kind == null || kind == 'igual') {
      // Semanal de un solo día: sigue al día nuevo.
      if (current.kind == RepeatKind.weekly && current.weekdays.length <= 1) {
        return Recurrence.weekly({due.weekday});
      }
      return current;
    }
    return switch (kind) {
      'daily' => const Recurrence.daily(),
      'weekly' => Recurrence.weekly({due.weekday}),
      'monthly' => const Recurrence.monthly(),
      'yearly' => const Recurrence.yearly(),
      _ => const Recurrence.none(),
    };
  }

  // --- La lista que lee Gmail ---

  Future<Map<String, dynamic>> _mainJson({
    required String? pair,
    required List<String> applied,
    required Map<String, int> refs,
    DateTime? now,
  }) async {
    now ??= DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final all = await reminders.watchAll().first;
    String hm(DateTime d) => DateFormat('HH:mm').format(d);
    return {
      'formato': mainFormat,
      'version': 1,
      'par': pair,
      'actualizado': now.toIso8601String(),
      'recordatorios': [
        for (final r in all)
          if (r.id != null)
            {
              'id': r.id,
              'titulo': r.title,
              'fecha': _day.format(r.dueAt),
              'hora': hm(r.dueAt),
              'repetir': r.recurrence.storageKind,
              'repite': r.repeats ? r.recurrence.describe(r.dueAt) : null,
              // La próxima vez (en los que se repiten, la de hoy cuenta).
              'proxima': _localIso(
                r.repeats
                    ? r.recurrence.nextAfter(
                            r.dueAt,
                            startOfToday.subtract(
                              const Duration(microseconds: 1),
                            ),
                          ) ??
                          r.dueAt
                    : r.dueAt,
              ),
              'hecho': r.done,
              'hechoEl': r.completedAt == null
                  ? null
                  : _localIso(r.completedAt!),
            },
      ],
      'aplicados': applied,
      'refs': refs,
    };
  }

  static String _localIso(DateTime d) =>
      DateFormat("yyyy-MM-dd'T'HH:mm").format(d);

  // --- Ayudantes ---

  static Uint8List _encode(Map<String, dynamic> data) => Uint8List.fromList(
    utf8.encode('${const JsonEncoder.withIndent(' ').convert(data)}\n'),
  );

  static Map<String, dynamic>? _decode(Uint8List bytes) {
    try {
      var text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return {'formato': changesFormat, 'cambios': []};
      // Por si quedó basura de una versión más larga del archivo.
      final end = text.lastIndexOf('}');
      if (end >= 0) text = text.substring(0, end + 1);
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static List<String> _readList(String? raw) {
    try {
      return [for (final e in jsonDecode(raw ?? '[]') as List) '$e'];
    } catch (_) {
      return [];
    }
  }

  static Map<String, int> _readRefs(String? raw) {
    try {
      return {
        for (final e in (jsonDecode(raw ?? '{}') as Map).entries)
          if (e.value is int) '${e.key}': e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return '${s.length}-$h';
  }

  static String _randomId(String prefix) {
    final r = Random.secure();
    return '$prefix-${List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }
}
