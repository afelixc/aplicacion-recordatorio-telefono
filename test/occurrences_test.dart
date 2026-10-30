import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/features/calendar/occurrences.dart';

void main() {
  final nov = DateTime(2026, 11);
  final dec = DateTime(2026, 12);

  test(
    'muestra los que no se repiten en su día y las repeticiones del mes',
    () {
      final byDay = occurrencesByDay(
        [
          Reminder(
            id: 1,
            title: 'Dentista',
            dueAt: DateTime(2026, 11, 3, 16, 30),
          ),
          Reminder(
            id: 2,
            title: 'Fuera del mes',
            dueAt: DateTime(2026, 12, 1, 9),
          ),
          Reminder(
            id: 3,
            title: 'Gimnasio',
            dueAt: DateTime(2026, 11, 2, 19),
            recurrence: Recurrence.weekly({DateTime.monday, DateTime.thursday}),
          ),
          Reminder(
            id: 4,
            title: 'Pagar alquiler',
            dueAt: DateTime(2026, 10, 10, 9),
            recurrence: const Recurrence.monthly(),
          ),
        ],
        nov,
        dec,
      );

      expect(byDay[DateTime(2026, 11, 3)]!.single.reminder.title, 'Dentista');
      expect(byDay[DateTime(2026, 12, 1)], isNull);
      // Lunes y jueves de noviembre desde el 2: 2,5,9,12,16,19,23,26,30.
      final gym = byDay.values
          .expand((l) => l)
          .where((o) => o.reminder.title == 'Gimnasio')
          .map((o) => o.at.day);
      expect(gym, [2, 5, 9, 12, 16, 19, 23, 26, 30]);
      expect(
        byDay[DateTime(2026, 11, 10)]!.single.reminder.title,
        'Pagar alquiler',
      );
    },
  );

  test(
    'no muestra repeticiones antes de la fecha de inicio ni las cortadas',
    () {
      final byDay = occurrencesByDay(
        [
          Reminder(
            id: 1,
            title: 'Desde el 20',
            dueAt: DateTime(2026, 11, 20, 8),
            recurrence: const Recurrence.daily(),
          ),
          Reminder(
            id: 2,
            title: 'Cortado',
            dueAt: DateTime(2026, 11, 1, 8),
            recurrence: const Recurrence.daily(),
            done: true,
          ),
        ],
        nov,
        dec,
      );
      expect(byDay.keys.map((d) => d.day).toList()..sort(), [
        for (var d = 20; d <= 30; d++) d,
      ]);
    },
  );

  test('ordena por hora dentro del día', () {
    final day = DateTime(2026, 11, 5);
    final byDay = occurrencesByDay(
      [
        Reminder(
          id: 1,
          title: 'Tarde',
          dueAt: day.add(const Duration(hours: 18)),
        ),
        Reminder(
          id: 2,
          title: 'Mañana',
          dueAt: day.add(const Duration(hours: 8)),
        ),
      ],
      nov,
      dec,
    );
    expect(byDay[day]!.map((o) => o.reminder.title), ['Mañana', 'Tarde']);
  });
}
