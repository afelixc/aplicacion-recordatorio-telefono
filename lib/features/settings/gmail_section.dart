import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../gmail/gmail_sync.dart';
import 'settings_screen.dart';

/// Dónde está el código del complemento para pegar en script.google.com.
const gmailAddonUrl =
    'https://github.com/afelixc/aplicacion-recordatorio-telefono/tree/main/gmail-addon';

/// Configuración → Gmail en la compu (recuadro escondido: 5 toques en la
/// versión). Une Recordame con el complemento de Gmail por dos archivos en
/// Drive.
class GmailSection extends StatefulWidget {
  const GmailSection({super.key, required this.gmail, this.onConnected});

  final GmailSync gmail;

  /// Al conectar: que la revisión con la app cerrada también mire Gmail.
  final Future<void> Function()? onConnected;

  @override
  State<GmailSection> createState() => _GmailSectionState();
}

class _GmailSectionState extends State<GmailSection> {
  bool _busy = false;

  AppSettings get _settings => widget.gmail.settings;

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
          duration: const Duration(seconds: 6),
          persist: false,
        ),
      );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _choose() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_to_drive),
        title: const Text('Dos archivos en la misma carpeta'),
        content: const Text(
          'Se va a abrir dos veces la ventana de "Guardar":\n\n'
          '1. Tocá ☰ (arriba a la izquierda) y elegí "Drive".\n'
          '2. Entrá a la carpeta que quieras (por ejemplo "Mi unidad").\n'
          '3. Tocá "Guardar" sin cambiar el nombre.\n\n'
          'La segunda vez, la MISMA carpeta y "Guardar" otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('gmail-choose-go'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _run(() async {
      if (!await widget.gmail.choose()) {
        _say('No se guardó: faltó tocar "Guardar" en alguna de las dos.');
        return;
      }
      await widget.onConnected?.call();
      _say(
        'Listo ✓ Ya están los dos archivos. Ahora seguí los pasos de la '
        'compu de acá abajo.',
      );
    });
  }

  Future<void> _syncNow() => _run(() async {
    final n = await widget.gmail.sync(force: true);
    if (n == null) {
      _say(_settings.gmailError ?? 'No pude actualizar.', error: true);
    } else {
      _say(
        n == 0
            ? 'Listo ✓ Gmail ya tiene todo al día.'
            : 'Listo ✓ Llegaron $n cambios de la compu.',
      );
    }
  });

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desconectar Gmail?'),
        content: const Text(
          'Recordame deja de actualizar los archivos de Drive y no levanta '
          'más lo que hagas en Gmail. Tus recordatorios no se borran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.gmail.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _settings;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        SettingsCard(
          title: 'Recordame en la barra de Gmail',
          children: [
            const Text(
              'Ves y manejás tus recordatorios desde Gmail en la compu: '
              'tildar, crear, cambiar y borrar. Lo que hagas de un lado se '
              'pasa al otro.',
            ),
            if (!s.gmailOn) ...[
              FilledButton.icon(
                key: const Key('gmail-choose'),
                icon: const Icon(Icons.add_to_drive),
                label: const Text('Elegir dónde se guarda en Drive'),
                onPressed: _busy ? null : _choose,
              ),
            ] else ...[
              _Status(last: s.gmailLast, error: s.gmailError),
              FilledButton.icon(
                key: const Key('gmail-sync'),
                icon: const Icon(Icons.sync),
                label: const Text('Actualizar ahora'),
                onPressed: _busy ? null : _syncNow,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('Elegir dónde se guarda de nuevo'),
                onPressed: _busy ? null : _choose,
              ),
              TextButton(
                onPressed: _busy ? null : _disconnect,
                child: const Text('Desconectar'),
              ),
            ],
          ],
        ),
        SettingsCard(
          title: 'Cuánto tarda',
          children: [
            const Text(
              '• Del teléfono a Gmail: de unos segundos a un par de minutos. '
              'En Gmail tocá ⟳ para ver lo último.\n'
              '• De Gmail al teléfono: enseguida si Recordame está abierto '
              '(mira cada minuto). Con la app cerrada, cada 15 minutos más '
              'o menos. Recién ahí el teléfono programa el aviso.',
            ),
          ],
        ),
        SettingsCard(
          title: 'En la compu (una sola vez)',
          children: [
            const Text(
              '1. Entrá a script.google.com con la cuenta de Gmail donde lo '
              'querés ver y tocá "Nuevo proyecto". Nombre: Recordame.\n'
              '2. En la ruedita ⚙ tildá "Mostrar el archivo de manifiesto '
              '«appsscript.json»".\n'
              '3. Abrí el link de abajo y copiá los 2 archivos: '
              'appsscript.json y Codigo.gs, cada uno en el suyo.\n'
              '4. Implementar → Implementaciones de prueba → Instalar.\n'
              '5. Abrí Gmail y recargá la página: a la derecha aparece la '
              'campanita de Recordame.\n'
              '6. La primera vez dice "Google no verificó esta app": es '
              'normal porque es tuya. Configuración avanzada → Ir a '
              'Recordame → Permitir.',
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar el link de los 2 archivos'),
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: gmailAddonUrl),
                );
                _say('Link copiado. Mandátelo por mail o WhatsApp a la compu.');
              },
            ),
            Text(
              'Si el Drive del teléfono es de otra cuenta que el Gmail de la '
              'compu: en drive.google.com compartí la carpeta con la cuenta '
              'de Gmail, con permiso de "Editor".',
              style: hint,
            ),
          ],
        ),
        TextButton(
          onPressed: () => s.setGmailUnlocked(false),
          child: const Text('Esconder este recuadro de Configuración'),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.last, required this.error});

  final DateTime? last;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad = error != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bad ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(
            bad ? Icons.error_outline : Icons.check_circle,
            color: bad ? scheme.error : scheme.primary,
          ),
          Expanded(
            child: Text(
              bad
                  ? error!
                  : last == null
                  ? 'Conectado ✓'
                  : 'Conectado ✓ · última actualización: ${Fmt.when(last!)}',
            ),
          ),
        ],
      ),
    );
  }
}
