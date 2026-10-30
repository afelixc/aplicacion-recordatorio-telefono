import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';

/// Formulario de título, día y hora. Se usa para crear y editar recordatorios,
/// en el modo gratis del chat y, más adelante, para corregir lo que arme la IA.
class ReminderForm extends StatefulWidget {
  const ReminderForm({
    super.key,
    this.initial,
    required this.submitLabel,
    required this.onSubmit,
    this.onCancel,
  });

  final Reminder? initial;
  final String submitLabel;
  final ValueChanged<Reminder> onSubmit;
  final VoidCallback? onCancel;

  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late DateTime _day;
  late TimeOfDay _time;
  late RepeatKind _repeat;
  late Set<int> _weekdays;
  late List<DateTime> _dates;
  String? _repeatError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final due = initial?.dueAt ?? _defaultDue();
    _title = TextEditingController(text: initial?.title ?? '');
    _day = DateTime(due.year, due.month, due.day);
    _time = TimeOfDay.fromDateTime(due);
    final rule = initial?.recurrence ?? const Recurrence.none();
    _repeat = rule.kind;
    _weekdays = {...rule.weekdays};
    _dates = [...rule.dates];
  }

  /// Por defecto: la próxima hora en punto.
  static DateTime _defaultDue() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// En "días puntuales" la fecha del recordatorio es la primera de la lista.
  DateTime get _dueAt {
    final day = _repeat == RepeatKind.dates && _dates.isNotEmpty
        ? (_dates.toList()..sort()).first
        : _day;
    return DateTime(day.year, day.month, day.day, _time.hour, _time.minute);
  }

  Recurrence get _recurrence => switch (_repeat) {
    RepeatKind.none => const Recurrence.none(),
    RepeatKind.daily => const Recurrence.daily(),
    RepeatKind.weekly => Recurrence.weekly(_weekdays),
    RepeatKind.monthly => const Recurrence.monthly(),
    RepeatKind.yearly => const Recurrence.yearly(),
    RepeatKind.dates => Recurrence.dates(_dates),
  };

  void _setRepeat(RepeatKind kind) {
    setState(() {
      _repeat = kind;
      _repeatError = null;
      if (kind == RepeatKind.weekly && _weekdays.isEmpty) {
        _weekdays = {_day.weekday};
      }
      if (kind == RepeatKind.dates && _dates.isEmpty) _dates = [_day];
    });
  }

  Future<void> _addDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dates.isEmpty ? _day : _dates.last,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: 'Agregar un día',
    );
    if (picked == null) return;
    setState(() {
      _repeatError = null;
      if (!_dates.contains(picked)) _dates = [..._dates, picked]..sort();
    });
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    final repeatError = switch (_repeat) {
      RepeatKind.weekly when _weekdays.isEmpty => 'Elegí al menos un día',
      RepeatKind.dates when _dates.isEmpty => 'Agregá al menos un día',
      _ => null,
    };
    setState(() => _repeatError = repeatError);
    if (!_formKey.currentState!.validate() || repeatError != null) return;
    final base = widget.initial;
    widget.onSubmit(
      base == null
          ? Reminder(
              title: _title.text.trim(),
              dueAt: _dueAt,
              recurrence: _recurrence,
            )
          : base.copyWith(
              title: _title.text.trim(),
              dueAt: _dueAt,
              recurrence: _recurrence,
              clearSnoozedUntil: true,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPast =
        _repeat == RepeatKind.none && _dueAt.isBefore(DateTime.now());
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('reminder-title'),
            controller: _title,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Qué',
              hintText: 'Ej: Lavar el auto',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Escribí qué recordar' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_repeat != RepeatKind.dates) ...[
                Expanded(
                  flex: 3,
                  child: _PickerField(
                    label: _repeat == RepeatKind.none ? 'Día' : 'Desde el',
                    icon: Icons.event,
                    value: Fmt.day(_day),
                    onTap: _pickDay,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: _PickerField(
                  label: 'Hora',
                  icon: Icons.schedule,
                  value: Fmt.time(_dueAt),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RepeatKind>(
            key: const Key('reminder-repeat'),
            initialValue: _repeat,
            decoration: const InputDecoration(
              labelText: 'Repetir',
              prefixIcon: Icon(Icons.repeat),
            ),
            items: const [
              DropdownMenuItem(
                value: RepeatKind.none,
                child: Text('No se repite'),
              ),
              DropdownMenuItem(
                value: RepeatKind.daily,
                child: Text('Todos los días'),
              ),
              DropdownMenuItem(
                value: RepeatKind.weekly,
                child: Text('Todas las semanas'),
              ),
              DropdownMenuItem(
                value: RepeatKind.monthly,
                child: Text('Todos los meses'),
              ),
              DropdownMenuItem(
                value: RepeatKind.yearly,
                child: Text('Todos los años'),
              ),
              DropdownMenuItem(
                value: RepeatKind.dates,
                child: Text('Días puntuales'),
              ),
            ],
            onChanged: (k) => _setRepeat(k ?? RepeatKind.none),
          ),
          if (_repeat == RepeatKind.weekly) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (day, label) in const [
                  (DateTime.monday, 'Lu'),
                  (DateTime.tuesday, 'Ma'),
                  (DateTime.wednesday, 'Mi'),
                  (DateTime.thursday, 'Ju'),
                  (DateTime.friday, 'Vi'),
                  (DateTime.saturday, 'Sá'),
                  (DateTime.sunday, 'Do'),
                ])
                  FilterChip(
                    label: Text(label),
                    showCheckmark: false,
                    selected: _weekdays.contains(day),
                    onSelected: (on) => setState(() {
                      _repeatError = null;
                      _weekdays = on
                          ? {..._weekdays, day}
                          : ({..._weekdays}..remove(day));
                    }),
                  ),
              ],
            ),
          ],
          if (_repeat == RepeatKind.dates) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in _dates)
                  InputChip(
                    label: Text(Fmt.shortDay(d)),
                    onDeleted: () =>
                        setState(() => _dates = [..._dates]..remove(d)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar día'),
                  onPressed: _addDate,
                ),
              ],
            ),
          ],
          if (_repeat != RepeatKind.none && _repeat != RepeatKind.dates) ...[
            const SizedBox(height: 6),
            Text(
              '${_recurrence.describe(_dueAt)} a las ${Fmt.time(_dueAt)} h',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_repeatError != null) ...[
            const SizedBox(height: 6),
            Text(
              _repeatError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (isPast) ...[
            const SizedBox(height: 8),
            Text(
              'Ojo: esa fecha y hora ya pasaron.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.onCancel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(widget.submitLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
