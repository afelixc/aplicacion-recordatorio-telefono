import 'dart:async';

/// Una consulta a la IA: cuándo, con qué modelo y cuánto costó (estimado).
class UsageRecord {
  const UsageRecord({
    this.id,
    required this.at,
    required this.provider,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    this.costUsd,
  });

  final int? id;
  final DateTime at;
  final String provider;
  final String model;
  final int inputTokens;
  final int outputTokens;

  /// Costo estimado en dólares; null si no se conoce el precio del modelo.
  final double? costUsd;
}

/// Registro local de las consultas a la IA.
abstract class UsageRepository {
  Future<void> record(UsageRecord record);

  /// Consultas desde [from], de la más vieja a la más nueva.
  Stream<List<UsageRecord>> watchSince(DateTime from);
}

class MemoryUsageRepository implements UsageRepository {
  MemoryUsageRepository([List<UsageRecord> initial = const []])
    : _items = [...initial];

  final List<UsageRecord> _items;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> record(UsageRecord record) async {
    _items.add(record);
    _changes.add(null);
  }

  List<UsageRecord> _since(DateTime from) =>
      _items.where((r) => !r.at.isBefore(from)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));

  @override
  Stream<List<UsageRecord>> watchSince(DateTime from) async* {
    yield _since(from);
    yield* _changes.stream.map((_) => _since(from));
  }
}
