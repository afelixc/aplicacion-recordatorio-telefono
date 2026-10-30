import 'dart:async';

import 'reminder.dart';
import 'reminder_repository.dart';

/// Guarda los recordatorios solo en memoria. Se usa en las pruebas y en la
/// vista previa web, donde no hay base de datos del teléfono.
class MemoryReminderRepository implements ReminderRepository {
  MemoryReminderRepository([List<Reminder> initial = const []]) {
    for (final r in initial) {
      final id = ++_lastId;
      _items[id] = r.copyWith(id: id);
    }
  }

  final _items = <int, Reminder>{};
  final _controller = StreamController<List<Reminder>>.broadcast();
  int _lastId = 0;

  List<Reminder> get _sorted =>
      _items.values.toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  void _emit() => _controller.add(_sorted);

  @override
  Stream<List<Reminder>> watchAll() async* {
    yield _sorted;
    yield* _controller.stream;
  }

  @override
  Future<Reminder?> getById(int id) async => _items[id];

  @override
  Future<Reminder> save(Reminder reminder) async {
    final saved = reminder.copyWith(id: reminder.id ?? ++_lastId);
    _items[saved.id!] = saved;
    _emit();
    return saved;
  }

  @override
  Future<void> setDone(int id, bool done) async {
    final r = _items[id];
    if (r == null) return;
    _items[id] = r.copyWith(
      done: done,
      completedAt: done ? DateTime.now() : null,
      clearCompletedAt: !done,
    );
    _emit();
  }

  @override
  Future<void> delete(int id) async {
    _items.remove(id);
    _emit();
  }
}
