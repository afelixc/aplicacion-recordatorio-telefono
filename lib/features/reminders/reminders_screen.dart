import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/reminder.dart';
import 'reminder_editor.dart';
import 'reminder_tile.dart';

enum _Filter { pending, done, all }

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  _Filter _filter = _Filter.pending;

  bool _matches(Reminder r) => switch (_filter) {
    _Filter.pending => !r.done,
    _Filter.done => r.done,
    _Filter.all => true,
  };

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).reminders;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showReminderEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Filter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _Filter.pending,
                    label: Text('Pendientes'),
                  ),
                  ButtonSegment(value: _Filter.done, label: Text('Hechos')),
                  ButtonSegment(value: _Filter.all, label: Text('Todos')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Reminder>>(
              stream: repo.watchAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snapshot.data!.where(_matches).toList();
                // Los hechos, del más reciente al más viejo.
                if (_filter == _Filter.done) items = items.reversed.toList();
                if (items.isEmpty) return _Empty(filter: _filter);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => ReminderTile(
                    key: ValueKey(items[i].id),
                    reminder: items[i],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final text = switch (filter) {
      _Filter.pending =>
        'No tenés recordatorios pendientes.\nTocá "Nuevo" para cargar uno.',
      _Filter.done => 'Todavía no marcaste ninguno como hecho.',
      _Filter.all =>
        'Todavía no cargaste recordatorios.\nTocá "Nuevo" para empezar.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
