import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/data/recurrence.dart';
import 'package:recordame/features/reminders/multi_day_picker.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('selección', () {
    test('fechas sueltas', () {
      final s = DaySelection();
      s.toggleDate(DateTime(2026, 11, 1));
      s.toggleDate(DateTime(2026, 11, 10, 15)); // la hora no importa
      s.toggleDate(DateTime(2026, 11, 20));
      s.toggleDate(DateTime(2026, 11, 20)); // tocar de nuevo la saca
      final r = s.toRecurrence()!;
      expect(r.kind, RepeatKind.dates);
      expect(r.dates, [DateTime(2026, 11, 1), DateTime(2026, 11, 10)]);
    });

    test('días de la semana', () {
      final s = DaySelection();
      for (final d in [1, 3, 5, 7]) {
        s.toggleWeekday(d);
      }
      final r = s.toRecurrence()!;
      expect(r.kind, RepeatKind.weekly);
      expect(r.weekdays, {1, 3, 5, 7});
      expect(s.isSelected(DateTime(2026, 11, 2)), isTrue); // lunes
      expect(s.isSelected(DateTime(2026, 11, 3)), isFalse); // martes
    });

    test('cambiar de modo borra lo anterior y avisa', () {
      final s = DaySelection();
      expect(s.toggleDate(DateTime(2026, 11, 1)), isFalse);
      expect(s.toggleWeekday(1), isTrue);
      expect(s.dates, isEmpty);
      expect(s.toggleDate(DateTime(2026, 11, 5)), isTrue);
      expect(s.weekdays, isEmpty);
      expect(s.toRecurrence()!.kind, RepeatKind.dates);
    });

    test('vacío', () {
      expect(DaySelection().toRecurrence(), isNull);
    });
  });

  testWidgets('se eligen varios días tocando los números', (tester) async {
    Recurrence? result;
    final nextMonth = DateTime(DateTime.now().year, DateTime.now().month + 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showMultiDayPicker(
                context,
                initialMonth: nextMonth,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    for (final d in [1, 10, 20]) {
      await tester.ensureVisible(find.byKey(ValueKey('day-$d')));
      await tester.tap(find.byKey(ValueKey('day-$d')));
      await tester.pump();
    }
    expect(find.textContaining('3 días'), findsOneWidget);
    await tester.ensureVisible(find.text('Listo'));
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();

    expect(result!.kind, RepeatKind.dates);
    expect(result!.dates.map((d) => d.day), [1, 10, 20]);
  });

  testWidgets('se eligen días de la semana tocando las letras', (tester) async {
    Recurrence? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showMultiDayPicker(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    for (final d in [1, 3, 5, 7]) {
      await tester.tap(find.byKey(ValueKey('weekday-$d')));
      await tester.pump();
    }
    expect(
      find.text('Todos los lunes, miércoles, viernes y domingos'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Listo'));
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();

    expect(result!.kind, RepeatKind.weekly);
    expect(result!.weekdays, {1, 3, 5, 7});
  });
}
