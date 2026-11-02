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
import 'package:recordame/features/gmail/gmail_sync.dart';

/// Drive de mentira: archivos en memoria.
class FakeFiles implements GmailFiles {
  final files = <String, Uint8List>{};
  var writes = 0;

  @override
  Future<String?> create(String name, Uint8List data) async {
    files[name] = data;
    return name;
  }

  @override
  Future<bool> write(String uri, Uint8List data) async {
    writes++;
    files[uri] = data;
    return true;
  }

  @override
  Future<Uint8List?> read(String uri) async => files[uri];

  Map<String, dynamic> json(String name) =>
      jsonDecode(utf8.decode(files[name]!)) as Map<String, dynamic>;

  /// Lo que haría el complemento de Gmail: anotar cambios.
  void gmailWrites(List<Map<String, dynamic>> ops) {
    final c = json(GmailSync.changesName);
    files[GmailSync.changesName] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          ...c,
          'cambios': [...(c['cambios'] as List), ...ops],
        }),
      ),
    );
  }
}

Future<(GmailSync, MemoryReminderRepository, FakeFiles)> make({
  List<Reminder> initial = const [],
}) async {
  final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
  await settings.load(['claude']);
  final repo = MemoryReminderRepository(initial);
  final files = FakeFiles();
  final gmail = GmailSync(reminders: repo, settings: settings, files: files);
  return (gmail, repo, files);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));
  final at = DateTime(2026, 12, 10, 18, 30);

  test('elegir crea los dos archivos con la lista', () async {
    final (gmail, _, files) = await make(
      initial: [Reminder(title: 'Pagar la luz', dueAt: at)],
    );
    expect(await gmail.choose(), isTrue);
    expect(gmail.settings.gmailOn, isTrue);
    final main = files.json(GmailSync.mainName);
    expect(main['formato'], 'recordame-gmail');
    final r = (main['recordatorios'] as List).single as Map;
    expect(r['titulo'], 'Pagar la luz');
    expect(r['fecha'], '2026-12-10');
    expect(r['hora'], '18:30');
    expect(files.json(GmailSync.changesName)['par'], main['par']);
  });

  test('de Gmail al teléfono: crear, modificar, tildar y borrar', () async {
    final (gmail, repo, files) = await make(
      initial: [
        Reminder(title: 'Uno', dueAt: at),
        Reminder(title: 'Dos', dueAt: at),
      ],
    );
    await gmail.choose();
    files.gmailWrites([
      {
        'id': 'op-1',
        'tipo': 'crear',
        'rec': 'pc-a',
        'titulo': 'Llamar a Fabricio',
        'fecha': '2026-12-11',
        'hora': '09:15',
        'repetir': 'weekly',
      },
      {'id': 'op-2', 'tipo': 'hecho', 'rec': '1'},
      {
        'id': 'op-3',
        'tipo': 'modificar',
        'rec': '2',
        'titulo': 'Dos cambiado',
        'fecha': '2026-12-20',
        'hora': '07:00',
        'repetir': 'igual',
      },
      {'id': 'op-4', 'tipo': 'hecho', 'rec': 'pc-a'},
    ]);
    expect(await gmail.sync(), 4);
    final all = {for (final r in await repo.watchAll().first) r.title: r};
    expect(all['Uno']!.done, isTrue);
    expect(all['Dos cambiado']!.dueAt, DateTime(2026, 12, 20, 7));
    final created = all['Llamar a Fabricio']!;
    expect(created.dueAt, DateTime(2026, 12, 11, 9, 15));
    expect(created.recurrence.kind, RepeatKind.weekly);
    expect(created.done, isTrue);

    // La lista avisa qué cambios ya se aplicaron y a qué id fue "pc-a".
    final main = files.json(GmailSync.mainName);
    expect(main['aplicados'], containsAll(['op-1', 'op-2', 'op-3', 'op-4']));
    expect(main['refs'], {'pc-a': created.id});

    // Leer de nuevo no repite nada.
    expect(await gmail.sync(), 0);
    expect((await repo.watchAll().first).length, 3);

    files.gmailWrites([
      {'id': 'op-5', 'tipo': 'borrar', 'rec': 'pc-a'},
      {'id': 'op-6', 'tipo': 'pendiente', 'rec': '1'},
    ]);
    await gmail.sync();
    final left = await repo.watchAll().first;
    expect(left.map((r) => r.title), isNot(contains('Llamar a Fabricio')));
    expect(left.firstWhere((r) => r.title == 'Uno').done, isFalse);
  });

  test('del teléfono a Gmail: solo escribe si cambió algo', () async {
    final (gmail, repo, files) = await make(
      initial: [Reminder(title: 'Uno', dueAt: at)],
    );
    await gmail.choose();
    await gmail.sync();
    final before = files.writes;
    await gmail.sync();
    expect(files.writes, before);

    await repo.setDone(1, true);
    await gmail.sync();
    expect(files.writes, before + 1);
    final r = (files.json(GmailSync.mainName)['recordatorios'] as List).single;
    expect((r as Map)['hecho'], isTrue);
  });

  test('cambios de otro par de archivos no se aplican', () async {
    final (gmail, repo, files) = await make();
    await gmail.choose();
    files.files[GmailSync.changesName] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'formato': 'recordame-gmail-cambios',
          'par': 'par-otro',
          'cambios': [
            {'id': 'op-1', 'tipo': 'crear', 'rec': 'pc-a', 'titulo': 'X'},
          ],
        }),
      ),
    );
    expect(await gmail.sync(), 0);
    expect(await repo.watchAll().first, isEmpty);
  });

  testWidgets('5 toques en la versión muestran "Gmail en la compu"', (
    tester,
  ) async {
    final (gmail, repo, files) = await make(
      initial: [Reminder(title: 'Uno', dueAt: at)],
    );
    await tester.pumpWidget(
      RecordameApp(reminders: repo, settings: gmail.settings, gmail: gmail),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.text('Gmail en la compu'), findsNothing);
    final footer = find.byKey(const Key('version-footer'));
    await tester.scrollUntilVisible(footer, 100);
    for (var i = 0; i < 5; i++) {
      await tester.tap(footer);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6)); // se va el cartel
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Gmail en la compu'), -100);
    await tester.tap(find.text('Gmail en la compu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gmail-choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gmail-choose-go')));
    await tester.pumpAndSettle();
    expect(gmail.settings.gmailOn, isTrue);
    expect(files.files.keys, contains(GmailSync.changesName));
    expect(find.byKey(const Key('gmail-sync')), findsOneWidget);
  });
}
