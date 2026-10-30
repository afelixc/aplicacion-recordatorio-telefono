import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/usage.dart';
import 'package:recordame/features/settings/usage_section.dart';

UsageRecord _r(DateTime at, double? cost) => UsageRecord(
  at: at,
  provider: 'claude',
  model: 'claude-haiku-5-5',
  inputTokens: 1000,
  outputTokens: 200,
  costUsd: cost,
);

void main() {
  final now = DateTime(2026, 11, 15, 18);

  test('suma hoy, el mes y descuenta del saldo anotado', () {
    final s = UsageSummary(
      [
        _r(DateTime(2026, 10, 31, 10), 0.5), // mes anterior
        _r(DateTime(2026, 11, 3, 10), 0.25), // antes de anotar el saldo
        _r(DateTime(2026, 11, 10, 10), 0.10),
        _r(DateTime(2026, 11, 15, 9), 0.02),
        _r(DateTime(2026, 11, 15, 17), 0.03),
      ],
      now: now,
      balance: (5.0, DateTime(2026, 11, 5)),
    );
    expect(s.todayCount, 2);
    expect(s.todayCost, closeTo(0.05, 1e-9));
    expect(s.monthCount, 4);
    expect(s.monthCost, closeTo(0.40, 1e-9));
    expect(s.remaining, closeTo(5.0 - 0.15, 1e-9));
    expect(s.hasUnknownCost, isFalse);
  });

  test('arma los últimos 14 días, terminando hoy', () {
    final s = UsageSummary([
      _r(DateTime(2026, 11, 15, 9), 0.02),
      _r(DateTime(2026, 11, 2, 9), 0.01),
    ], now: now);
    expect(s.days.length, 14);
    expect(s.days.first.day, DateTime(2026, 11, 2));
    expect(s.days.last.day, DateTime(2026, 11, 15));
    expect(s.days.first.cost, closeTo(0.01, 1e-9));
    expect(s.days.last.count, 1);
    expect(s.remaining, isNull);
  });

  test('si falta el precio de algún modelo, se avisa', () {
    final s = UsageSummary([_r(DateTime(2026, 11, 15, 9), null)], now: now);
    expect(s.hasUnknownCost, isTrue);
  });

  test('formato en dólares', () {
    expect(usd(0.0012), 'US\$ 0.0012');
    expect(usd(1.5), 'US\$ 1.50');
    expect(usd(0), 'US\$ 0.00');
  });
}
