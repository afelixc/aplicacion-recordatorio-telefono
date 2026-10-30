import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/data/recurrence.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  // Viernes 6 de noviembre de 2026, 9:00.
  final start = DateTime(2026, 11, 6, 9);

  test('no se repite: solo la fecha de inicio', () {
    const r = Recurrence.none();
    expect(r.nextAfter(start, DateTime(2026, 11, 1)), start);
    expect(r.nextAfter(start, DateTime(2026, 11, 6, 9)), isNull);
  });

  test('todos los días', () {
    const r = Recurrence.daily();
    expect(r.nextAfter(start, DateTime(2026, 11, 1)), start);
    expect(
      r.nextAfter(start, DateTime(2026, 11, 10, 8)),
      DateTime(2026, 11, 10, 9),
    );
    expect(
      r.nextAfter(start, DateTime(2026, 11, 10, 9)),
      DateTime(2026, 11, 11, 9),
    );
  });

  test('todas las semanas, varios días', () {
    final r = Recurrence.weekly({DateTime.monday, DateTime.wednesday});
    // Desde el viernes 6: lunes 9, miércoles 11, lunes 16.
    expect(r.upcoming(start, start, 3), [
      DateTime(2026, 11, 9, 9),
      DateTime(2026, 11, 11, 9),
      DateTime(2026, 11, 16, 9),
    ]);
    expect(r.describe(start), 'Todos los lunes y miércoles');
  });

  test('todas las semanas sin días elegidos usa el día de inicio', () {
    final r = Recurrence.weekly({});
    expect(r.nextAfter(start, start), DateTime(2026, 11, 13, 9));
    expect(r.describe(start), 'Todos los viernes');
  });

  test('todos los meses, y si el mes es más corto usa el último día', () {
    const r = Recurrence.monthly();
    final day31 = DateTime(2027, 1, 31, 9);
    expect(r.upcoming(day31, day31, 3), [
      DateTime(2027, 2, 28, 9),
      DateTime(2027, 3, 31, 9),
      DateTime(2027, 4, 30, 9),
    ]);
  });

  test('todos los años', () {
    const r = Recurrence.yearly();
    expect(r.nextAfter(start, start), DateTime(2027, 11, 6, 9));
    expect(r.describe(start), 'Todos los años, el 6 de noviembre');
  });

  test('días puntuales, en orden y sin repetidos', () {
    final r = Recurrence.dates([
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 10),
      DateTime(2026, 11, 20),
    ]);
    expect(r.upcoming(start, DateTime(2026, 11, 1), 5), [
      DateTime(2026, 11, 10, 9),
      DateTime(2026, 11, 20, 9),
    ]);
    expect(r.nextAfter(start, DateTime(2026, 11, 21)), isNull);
    expect(r.describe(start), 'Días: 10/11, 20/11');
  });

  test('se guarda y se recupera igual', () {
    for (final r in [
      const Recurrence.none(),
      const Recurrence.daily(),
      Recurrence.weekly({1, 3, 7}),
      const Recurrence.monthly(),
      const Recurrence.yearly(),
      Recurrence.dates([DateTime(2026, 11, 10), DateTime(2026, 12, 1)]),
    ]) {
      final back = Recurrence.fromStorage(
        r.storageKind,
        r.storageWeekdays,
        r.storageDates,
      );
      expect(back.kind, r.kind);
      expect(back.weekdays, r.weekdays);
      expect(back.dates, r.dates);
    }
  });
}
