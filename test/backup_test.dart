import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/app.dart';
import 'package:recordame/core/settings.dart';
import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/data/usage.dart';
import 'package:recordame/features/backup/backup_service.dart';

/// Hace de cuenta que es Google Drive: guarda el archivo en memoria.
class _FakeFiles implements BackupFiles {
  Uint8List? stored;
  bool cancel = false;
  bool failWrite = false;

  @override
  Future<(String, String)?> create(String name, Uint8List data) async {
    if (cancel) return null;
    stored = data;
    return ('content://drive/1', name);
  }

  @override
  Future<bool> write(String uri, Uint8List data) async {
    if (failWrite) return false;
    stored = data;
    return true;
  }

  @override
  Future<Uint8List?> open() async => stored;
}

Future<(BackupService, MemoryReminderRepository, _FakeFiles)> _make({
  List<Reminder> reminders = const [],
  _FakeFiles? files,
  KeyStore? keys,
}) async {
  final repo = MemoryReminderRepository(reminders);
  final settings = AppSettings(MemorySettingsStore(), keys ?? MemoryKeyStore());
  await settings.load(['claude']);
  final f = files ?? _FakeFiles();
  return (
    BackupService(
      reminders: repo,
      usage: MemoryUsageRepository(),
      settings: settings,
      files: f,
    ),
    repo,
    f,
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  test(
    'guardar y recuperar en otro teléfono: vuelve todo, sin la clave',
    () async {
      final (a, _, files) = await _make(
        keys: MemoryKeyStore({'claude': 'sk-ant-secreta'}),
        reminders: [
          Reminder(title: 'Pagar la luz', dueAt: DateTime(2026, 11, 10, 9)),
          Reminder(
            title: 'Gimnasio',
            dueAt: DateTime(2026, 11, 2, 19, 30),
            recurrence: Recurrence.weekly({1, 4}),
          ),
          Reminder(
            title: 'Guitarra',
            dueAt: DateTime(2026, 11, 5, 18),
            recurrence: Recurrence.dates([
              DateTime(2026, 11, 5),
              DateTime(2026, 11, 12),
            ]),
            done: true,
            completedAt: DateTime(2026, 11, 1),
          ),
        ],
      );
      await a.settings.setMode(UsageMode.ai);
      await a.settings.setModel('claude', 'claude-sonnet-5-5');
      await a.settings.addChat(
        ChatEntry('hola', mine: true, at: DateTime(2026)),
      );
      await a.usage.record(
        UsageRecord(
          at: DateTime(2026, 10, 30),
          provider: 'claude',
          model: 'claude-haiku-5-5',
          inputTokens: 10,
          outputTokens: 5,
          costUsd: 0.001,
        ),
      );
      expect(await a.chooseAndSave(), isTrue);
      expect(a.settings.backupUri, 'content://drive/1');
      expect(utf8.decode(files.stored!), isNot(contains('sk-ant')));

      // Teléfono nuevo, con un recordatorio que se reemplaza.
      final (b, repoB, _) = await _make(
        files: files,
        reminders: [Reminder(title: 'Viejo', dueAt: DateTime(2026))],
      );
      final contents = await b.pickAndRead();
      await b.restore(contents!);
      final all = await repoB.watchAll().first;
      expect(
        all.map((r) => r.title),
        unorderedEquals(['Pagar la luz', 'Gimnasio', 'Guitarra']),
      );
      final gym = all.firstWhere((r) => r.title == 'Gimnasio');
      expect(gym.recurrence.weekdays, {1, 4});
      expect(gym.dueAt, DateTime(2026, 11, 2, 19, 30));
      final guitar = all.firstWhere((r) => r.title == 'Guitarra');
      expect(guitar.done, isTrue);
      expect(guitar.recurrence.dates.length, 2);
      expect(b.settings.mode, UsageMode.ai);
      expect(b.settings.modelFor('claude'), 'claude-sonnet-5-5');
      expect(b.settings.chatHistory.single.text, 'hola');
      expect((await b.usage.watchSince(DateTime(2000)).first).length, 1);
      expect(b.settings.hasKey('claude'), isFalse);
    },
  );

  test(
    'se lee aunque al archivo le quede basura de una copia más larga',
    () async {
      final (a, _, _) = await _make(
        reminders: [Reminder(title: 'Uno', dueAt: DateTime(2026, 11, 1))],
      );
      final bytes = await a.build();
      final dirty = Uint8List.fromList([
        ...bytes,
        ...utf8.encode('  }\n ]\n}\n'),
      ]);
      expect(BackupService.parse(dirty).reminders.single.title, 'Uno');
    },
  );

  test('un archivo que no es copia da un mensaje claro', () {
    expect(
      () => BackupService.parse(Uint8List.fromList(utf8.encode('{"a":1}'))),
      throwsA(isA<BackupException>()),
    );
  });

  test('copia automática: solo una vez por día', () async {
    final (a, _, files) = await _make();
    await a.autoBackup();
    expect(files.stored, isNull, reason: 'sin carpeta elegida no hace nada');
    await a.chooseAndSave();
    files.stored = null;
    await a.autoBackup();
    expect(files.stored, isNull, reason: 'recién se guardó');
    await a.autoBackup(now: DateTime.now().add(const Duration(hours: 25)));
    expect(files.stored, isNotNull);

    files.failWrite = true;
    await a.autoBackup(now: DateTime.now().add(const Duration(days: 3)));
    expect(a.settings.backupError, isNotNull);
  });

  testWidgets('Configuración → Copia de seguridad: guardar y recuperar', (
    tester,
  ) async {
    final (backup, repo, _) = await _make(
      reminders: [
        Reminder(title: 'Pagar la luz', dueAt: DateTime(2026, 12, 1, 9)),
      ],
    );
    await tester.pumpWidget(
      RecordameApp(reminders: repo, settings: backup.settings, backup: backup),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Copia de seguridad'), 100);
    await tester.tap(find.text('Copia de seguridad'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay copia'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup-choose')));
    await tester.pumpAndSettle();
    expect(find.text('Copia al día ✓'), findsOneWidget);
    expect(find.text('Guardar copia ahora'), findsOneWidget);

    // Se borra en el teléfono y se recupera de la copia, confirmando antes.
    await repo.delete((await repo.watchAll().first).single.id!);
    await tester.ensureVisible(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
    expect(find.text('¿Recuperar esta copia?'), findsOneWidget);
    expect(find.text('Cancelar (no cambia nada)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('restore-replace')));
    await tester.pumpAndSettle();
    expect((await repo.watchAll().first).single.title, 'Pagar la luz');
  });
}
