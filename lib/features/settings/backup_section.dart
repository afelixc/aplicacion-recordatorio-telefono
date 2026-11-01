import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../backup/backup_service.dart';
import 'settings_screen.dart';

/// Configuración → Copia de seguridad: guardar todo en un archivo (por
/// ejemplo en una carpeta de Google Drive) y recuperarlo.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.backup});

  final BackupService backup;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  AppSettings get _settings => widget.backup.settings;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_changed);
  }

  @override
  void dispose() {
    _settings.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? scheme.error : null,
          duration: const Duration(seconds: 5),
          persist: false,
        ),
      );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _say(e.message, error: true);
    } on PlatformException catch (e) {
      _say(
        e.message ?? 'No se pudo usar ese lugar. Probá con otro.',
        error: true,
      );
    } catch (_) {
      _say('Algo salió mal. Probá de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() => _run(() async {
    if (await widget.backup.chooseAndSave()) {
      _say('Listo ✓ Copia guardada. Desde ahora se actualiza sola cada día.');
    }
  });

  Future<void> _saveNow() => _run(() async {
    if (await widget.backup.saveNow()) {
      _say('Listo ✓ Copia actualizada.');
    } else {
      _say(_settings.backupError ?? 'No pude guardar la copia.', error: true);
    }
  });

  Future<void> _restore() async {
    BackupContents? contents;
    await _run(() async => contents = await widget.backup.pickAndRead());
    final c = contents;
    if (c == null || !mounted) return;
    await _confirmRestore(c);
  }

  Future<void> _confirmRestore(BackupContents contents) async {
    final pending = contents.reminders.where((r) => !r.done).length;
    final now = (await widget.backup.reminders.watchAll().first).length;
    if (!mounted) return;
    final total = contents.reminders.length;
    final choice = await showDialog<_Restore>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restore),
        title: const Text('¿Recuperar esta copia?'),
        content: Text(
          'Copia del ${Fmt.day(contents.createdAt)} a las '
          '${Fmt.time(contents.createdAt)}, con $total recordatorios '
          '($pending pendientes).\nAhora en el teléfono tenés $now.',
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          _ChoiceButton(
            key: const Key('restore-merge'),
            primary: true,
            title: 'Sumar los de la copia',
            detail: 'No borra nada: agrega los que faltan',
            onPressed: () => Navigator.pop(context, _Restore.merge),
          ),
          _ChoiceButton(
            key: const Key('restore-replace'),
            title: 'Reemplazar todo por la copia',
            detail: 'Borra los $now del teléfono y deja los $total de la copia',
            onPressed: () => Navigator.pop(context, _Restore.replace),
          ),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar (no cambia nada)'),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _run(() async {
      final merge = choice == _Restore.merge;
      final added = await widget.backup.restore(contents, merge: merge);
      _say(
        merge
            ? 'Listo ✓ Sumé $added de la copia. '
                  '${total - added == 0 ? '' : 'Los ${total - added} que ya estaban no se repitieron.'}'
            : 'Listo ✓ Ahora tenés los $total de la copia. '
                  'Si usás la IA, volvé a cargar la clave.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _settings;
    final has = s.backupUri != null;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        SettingsCard(
          title: 'Guardar copia',
          children: [
            _Status(
              has: has,
              name: s.backupName,
              last: s.backupLast,
              error: s.backupError,
            ),
            if (!has) ...[
              Text(
                'Se guardan tus recordatorios, el chat y tus preferencias en '
                'un archivo, en la carpeta que elijas. Te recomiendo Google '
                'Drive: así no se pierde aunque se rompa el teléfono.',
              ),
              FilledButton.icon(
                key: const Key('backup-choose'),
                icon: const Icon(Icons.add_to_drive),
                label: const Text('Elegir carpeta y guardar'),
                onPressed: _busy ? null : _choose,
              ),
              Text(
                'Se abre el selector de Android: tocá ☰ (arriba a la '
                'izquierda), elegí "Drive", entrá a la carpeta que quieras y '
                'tocá "Guardar".',
                style: hint,
              ),
            ] else ...[
              FilledButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Guardar copia ahora'),
                onPressed: _busy ? null : _saveNow,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('Cambiar dónde se guarda'),
                onPressed: _busy ? null : _choose,
              ),
            ],
          ],
        ),
        SettingsCard(
          title: 'Recuperar copia',
          children: [
            const Text(
              'Para un teléfono nuevo o si reinstalaste la app: elegí el '
              'archivo "Recordame-copia…" de tu Drive y vuelve todo.',
            ),
            OutlinedButton.icon(
              key: const Key('backup-restore'),
              icon: const Icon(Icons.restore),
              label: const Text('Recuperar desde un archivo'),
              onPressed: _busy ? null : _restore,
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'La clave de la IA no se guarda en la copia: queda solo en '
                'este teléfono. Si recuperás en otro, cargala de nuevo.',
                style: hint,
              ),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.has,
    required this.name,
    required this.last,
    required this.error,
  });

  final bool has;
  final String? name;
  final DateTime? last;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, bg, icon, title, detail) = switch ((has, error)) {
      (false, _) => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
        Icons.cloud_off,
        'Todavía no hay copia',
        'Elegí dónde guardarla con el botón de abajo.',
      ),
      (true, final String e) => (
        scheme.error,
        scheme.errorContainer,
        Icons.error,
        'La copia no se pudo actualizar',
        e,
      ),
      _ => (
        Colors.green.shade800,
        Colors.green.shade50,
        Icons.cloud_done,
        'Copia al día ✓',
        '${name ?? 'Recordame-copia'}'
            '${last == null ? '' : '\nÚltima: ${Fmt.when(last!)}'}'
            '\nSe actualiza sola una vez por día al usar la app.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Restore { merge, replace }

/// Botón ancho con título y una línea que explica qué hace.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.title,
    required this.detail,
    required this.onPressed,
    this.primary = false,
  });

  final String title;
  final String detail;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: primary
          ? FilledButton(style: style, onPressed: onPressed, child: child)
          : OutlinedButton(style: style, onPressed: onPressed, child: child),
    );
  }
}
