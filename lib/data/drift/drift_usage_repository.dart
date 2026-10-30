import 'package:drift/drift.dart';

import '../usage.dart';
import 'database.dart';

/// Guarda el registro de consumo de la IA en la base del teléfono.
class DriftUsageRepository implements UsageRepository {
  DriftUsageRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> record(UsageRecord r) async {
    await _db
        .into(_db.usageRecords)
        .insert(
          UsageRecordsCompanion.insert(
            at: r.at,
            provider: r.provider,
            model: r.model,
            inputTokens: r.inputTokens,
            outputTokens: r.outputTokens,
            costUsd: Value(r.costUsd),
          ),
        );
  }

  @override
  Stream<List<UsageRecord>> watchSince(DateTime from) {
    final query = _db.select(_db.usageRecords)
      ..where((t) => t.at.isBiggerOrEqualValue(from))
      ..orderBy([(t) => OrderingTerm.asc(t.at)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          UsageRecord(
            id: r.id,
            at: r.at,
            provider: r.provider,
            model: r.model,
            inputTokens: r.inputTokens,
            outputTokens: r.outputTokens,
            costUsd: r.costUsd,
          ),
      ],
    );
  }
}
