import 'package:flutter/material.dart';

import '../../core/formatting.dart';
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

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final due = initial?.dueAt ?? _defaultDue();
    _title = TextEditingController(text: initial?.title ?? '');
    _day = DateTime(due.year, due.month, due.day);
    _time = TimeOfDay.fromDateTime(due);
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

  DateTime get _dueAt =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

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
    if (!_formKey.currentState!.validate()) return;
    final base = widget.initial;
    widget.onSubmit(
      base == null
          ? Reminder(title: _title.text.trim(), dueAt: _dueAt)
          : base.copyWith(title: _title.text.trim(), dueAt: _dueAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPast = _dueAt.isBefore(DateTime.now());
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
              Expanded(
                flex: 3,
                child: _PickerField(
                  label: 'Día',
                  icon: Icons.event,
                  value: Fmt.day(_day),
                  onTap: _pickDay,
                ),
              ),
              const SizedBox(width: 8),
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
          if (isPast) ...[
            const SizedBox(height: 8),
            Text(
              'Ojo: esa fecha y hora ya pasaron.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
