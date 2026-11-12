import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/reminder.dart';
import '../../data/scheduling_reminder_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/notification_sound.dart';
import '../notifications/priority_config.dart';
import '../notifications/priority_sounds.dart';

/// Color de cada prioridad (las ventanitas y los botones del Chat).
Color priorityColor(ReminderPriority p) => switch (p) {
  ReminderPriority.normal => const Color(0xFF2E8B57),
  ReminderPriority.media => const Color(0xFFC27A00),
  ReminderPriority.alta => const Color(0xFFC43C3C),
};

String _raw(String id) => 'android.resource://com.afelixc.recordame/raw/$id';

/// Resumen chico de lo que hace cada prioridad.
String prioritySummary(ReminderPriority p, PriorityConfig c) => switch (p) {
  ReminderPriority.normal => 'Una vez',
  ReminderPriority.media => 'Cada ${c.mediaEvery} min',
  ReminderPriority.alta => '${c.altaTimes} veces, cada ${c.altaEvery} min',
};

/// "Prioridades de notificaciones": tres ventanitas chicas (cada una abre
/// sus opciones en grande), "Sonar en modo silencio" y un ejemplo.
class PrioritiesSection extends StatefulWidget {
  const PrioritiesSection({super.key, required this.service});

  final NotificationService service;

  @override
  State<PrioritiesSection> createState() => _PrioritiesSectionState();
}

class _PrioritiesSectionState extends State<PrioritiesSection> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.service.priorities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Prioridades de notificaciones',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in ReminderPriority.values) ...[
                if (p != ReminderPriority.normal) const SizedBox(width: 8),
                Expanded(
                  child: _Tile(
                    key: Key('prio-${p.name}'),
                    color: priorityColor(p),
                    title: p.label,
                    subtitle: prioritySummary(p, c),
                    onTap: () => _open(
                      PriorityPage(service: widget.service, priority: p),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            key: const Key('prio-silent'),
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Sonar en modo silencio'),
            subtitle: const Text('Se tilda en cada recordatorio'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const _SilentPage()),
          ),
        ),
        const SizedBox(height: 12),
        Text('Ejemplo: así te llega', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        const NotificationExample(),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dibujo de cómo se ve un aviso, con sus botones.
class NotificationExample extends StatelessWidget {
  const NotificationExample({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget button(String t) => Expanded(
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Llamar al contador por los papeles del auto',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text('Recordatorio · 10:00 h', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [button('HECHO'), button('1 HORA'), button('MAÑANA')]),
        ],
      ),
    );
  }
}

/// Opciones de una prioridad, en grande.
class PriorityPage extends StatefulWidget {
  const PriorityPage({
    super.key,
    required this.service,
    required this.priority,
  });

  final NotificationService service;
  final ReminderPriority priority;

  @override
  State<PriorityPage> createState() => _PriorityPageState();
}

class _PriorityPageState extends State<PriorityPage> {
  late PriorityConfig _c = widget.service.priorities;

  Future<void> _set(PriorityConfig c) async {
    setState(() => _c = c);
    final scope = AppScope.of(context);
    await widget.service.setPriorities(c);
    scope.settings.prioritiesRaw = c.encode();
    // Los avisos ya programados pasan a la configuración nueva.
    final repo = scope.reminders;
    if (repo is SchedulingReminderRepository) await repo.resync();
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.service.showPriorityTest(widget.priority);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
  }

  @override
  void dispose() {
    SoundPicker.stop();
    super.dispose();
  }

  Widget _box(List<Widget> children) {
    final color = priorityColor(widget.priority);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _choice<T>(
    String label,
    T value,
    List<T> options,
    String Function(T) text,
    ValueChanged<T> onChanged, {
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<T>(
          key: key,
          value: options.contains(value) ? value : options.first,
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(text(o))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    ),
  );

  Widget _sounds(
    List<(String, String, String?)> sounds,
    String current,
    ValueChanged<String> onPick,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final (id, name, uri) in sounds)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 4),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: id == current ? scheme.primary : scheme.outlineVariant,
                width: id == current ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                id == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: id == current ? scheme.primary : null,
              ),
              title: Text(name),
              trailing: IconButton(
                tooltip: 'Escuchar $name',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () => SoundPicker.play(uri),
              ),
              onTap: () {
                SoundPicker.play(uri);
                onPick(id);
              },
            ),
          ),
      ],
    );
  }

  String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.priority;
    final c = _c;
    final children = <Widget>[];
    final example = DateTime(2026, 1, 1, 10);
    String times(List<DateTime> l) => l.isEmpty
        ? 'no se repite'
        : '${l.take(5).map((t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}').join(' · ')}'
              '${l.length > 5 ? ' … (${l.length} veces)' : ''}';

    switch (p) {
      case ReminderPriority.normal:
        children.addAll([
          _box([
            const Text(
              'Avisa una vez, a la hora del recordatorio, con el sonido '
              'que elegiste para la app.',
            ),
            const SizedBox(height: 6),
            Text(
              'Sonido de la app: ${widget.service.soundName}. Se cambia en '
              'Notificaciones → Sonido del aviso.',
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ]);
      case ReminderPriority.media:
        children.addAll([
          _box([
            _choice(
              'Repetir cada',
              c.mediaEvery,
              PriorityConfig.everyOptions,
              (v) => '$v min',
              (v) => _set(c.copyWith(mediaEvery: v)),
              key: const Key('media-every'),
            ),
            _choice<int>(
              'Durante',
              c.mediaInHours ? -1 : c.mediaFor,
              [...PriorityConfig.mediaForOptions, -1],
              (v) => v == -1 ? 'En un horario' : PriorityConfig.forLabel(v),
              (v) => _set(
                v == -1
                    ? c.copyWith(mediaInHours: true)
                    : c.copyWith(mediaInHours: false, mediaFor: v),
              ),
              key: const Key('media-for'),
            ),
            if (c.mediaInHours) ...[
              _choice(
                'Desde',
                c.mediaFrom,
                [for (var h = 0; h < 24; h++) h],
                _hour,
                (v) => _set(c.copyWith(mediaFrom: v)),
              ),
              _choice(
                'Hasta',
                c.mediaTo,
                [for (var h = 1; h <= 24; h++) h],
                _hour,
                (v) => _set(c.copyWith(mediaTo: v)),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Si es a las 10:00: ${times(c.mediaRepeats(example))}.\n'
              'Se corta cuando tocás "Hecho".',
              style: theme.textTheme.bodySmall,
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            'Sonido de la prioridad media',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          _sounds(
            [
              (
                PriorityConfig.appSound,
                'El de la app (${widget.service.soundName})',
                widget.service.soundUri,
              ),
              for (final s in mediaSounds) (s.id, s.name, _raw(s.id)),
            ],
            c.mediaSound,
            (id) => _set(c.copyWith(mediaSound: id)),
          ),
        ]);
      case ReminderPriority.alta:
        children.addAll([
          _box([
            _choice(
              'Cuántas veces suena seguido',
              c.altaTimes,
              PriorityConfig.timesOptions,
              (v) => '$v',
              (v) => _set(c.copyWith(altaTimes: v)),
              key: const Key('alta-times'),
            ),
            _choice(
              'Repetir cada',
              c.altaEvery,
              PriorityConfig.altaEveryOptions,
              (v) => '$v min',
              (v) => _set(c.copyWith(altaEvery: v)),
            ),
            _choice(
              'Durante',
              c.altaFor,
              PriorityConfig.altaForOptions,
              (v) => PriorityConfig.forLabel(v, alta: true),
              (v) => _set(c.copyWith(altaFor: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrar fuerte'),
              value: c.altaVibrate,
              onChanged: (v) => _set(c.copyWith(altaVibrate: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pantalla completa, como alarma'),
              value: c.altaFullScreen,
              onChanged: (v) async {
                if (v) await widget.service.requestFullScreen();
                await _set(c.copyWith(altaFullScreen: v));
              },
            ),
            Text(
              'Si es a las 10:00: ${times(c.altaRepeats(example))}.\n'
              'Se corta cuando tocás "Hecho".',
              style: theme.textTheme.bodySmall,
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            'Musiquita de la prioridad alta',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          _sounds(
            [for (final s in altaSounds) (s.id, s.name, _raw(s.id))],
            c.altaSound,
            (id) => _set(c.copyWith(altaSound: id)),
          ),
        ]);
    }
    children.addAll([
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const Key('priority-test'),
        style: FilledButton.styleFrom(backgroundColor: priorityColor(p)),
        icon: const Icon(Icons.notifications_active_outlined),
        label: Text(
          p == ReminderPriority.alta
              ? 'Probar cómo suena (${c.altaTimes} veces)'
              : 'Probar un aviso',
        ),
        onPressed: _test,
      ),
    ]);
    return Scaffold(
      appBar: AppBar(title: Text('Prioridad ${p.label.toLowerCase()}')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }
}

class _SilentPage extends StatelessWidget {
  const _SilentPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sonar en modo silencio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'No está prendido para todos. Lo elegís en cada recordatorio, con '
            'el tildecito "Sonar aunque esté en silencio" que aparece debajo '
            'de Normal · Media · Alta.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Esos avisos suenan con el volumen de la alarma del teléfono, '
            'como el despertador. Si el volumen de la alarma está en cero, '
            'no se escuchan.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
