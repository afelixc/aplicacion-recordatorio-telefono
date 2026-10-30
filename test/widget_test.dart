import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/app.dart';
import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  Future<MemoryReminderRepository> pumpApp(
    WidgetTester tester, [
    List<Reminder> initial = const [],
  ]) async {
    final repo = MemoryReminderRepository(initial);
    await tester.pumpWidget(RecordameApp(reminders: repo));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('Muestra las cuatro pestañas', (tester) async {
    await pumpApp(tester);
    expect(find.text('Recordame'), findsOneWidget);
    for (final label in ['Chat', 'Almanaque', 'Listado', 'Configuración']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('Carga un recordatorio desde el chat y aparece en el listado', (
    tester,
  ) async {
    final repo = await pumpApp(tester);

    await tester.enterText(
      find.byKey(const Key('reminder-title')),
      'Lavar el auto',
    );
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Guardado ✓ "Lavar el auto"'), findsOneWidget);
    expect((await repo.watchAll().first).single.title, 'Lavar el auto');

    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    expect(find.text('Lavar el auto'), findsOneWidget);
  });

  testWidgets('No deja guardar sin título', (tester) async {
    final repo = await pumpApp(tester);
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();
    expect(find.text('Escribí qué recordar'), findsOneWidget);
    expect(await repo.watchAll().first, isEmpty);
  });

  testWidgets('Marca como hecho y borra desde el listado', (tester) async {
    final due = DateTime.now().add(const Duration(days: 1));
    final repo = await pumpApp(tester, [
      Reminder(title: 'Pagar la luz', dueAt: due),
      Reminder(
        title: 'Sacar la basura',
        dueAt: due.add(const Duration(hours: 1)),
      ),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();

    // Marcar "Pagar la luz" como hecho: sale de Pendientes y aparece en Hechos.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Pagar la luz'), findsNothing);
    await tester.tap(find.text('Hechos'));
    await tester.pumpAndSettle();
    expect(find.text('Pagar la luz'), findsOneWidget);

    // Borrar "Sacar la basura".
    await tester.tap(find.text('Pendientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Sacar la basura'), findsNothing);
    expect((await repo.watchAll().first).length, 1);
  });

  testWidgets('Edita un recordatorio', (tester) async {
    final repo = await pumpApp(tester, [
      Reminder(
        title: 'Turno',
        dueAt: DateTime.now().add(const Duration(days: 2)),
      ),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reminder-title')),
      'Turno con el dentista',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Turno con el dentista'), findsOneWidget);
    expect((await repo.watchAll().first).single.title, 'Turno con el dentista');
  });

  testWidgets('Carga un recordatorio que se repite varios días por semana', (
    tester,
  ) async {
    final repo = await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('reminder-title')), 'Gimnasio');

    await tester.tap(find.byKey(const Key('reminder-repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las semanas').last);
    await tester.pumpAndSettle();

    // Viene marcado el día elegido; sumar lunes y jueves (si no estaban).
    for (final day in ['Lu', 'Ju']) {
      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, day),
      );
      if (!chip.selected) {
        await tester.tap(find.widgetWithText(FilterChip, day));
        await tester.pumpAndSettle();
      }
    }
    await tester.ensureVisible(find.text('Guardar recordatorio'));
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchAll().first).single;
    expect(saved.recurrence.kind, RepeatKind.weekly);
    expect(
      saved.recurrence.weekdays,
      containsAll([DateTime.monday, DateTime.thursday]),
    );
    expect(
      find.textContaining('Guardado ✓ "Gimnasio", Todos los'),
      findsOneWidget,
    );
  });
}
