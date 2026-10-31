import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_providers.dart';
import '../ai/pricing.dart';
import 'settings_screen.dart';

/// Proveedor de IA, clave, modelo e instructivo.
class AiSection extends StatefulWidget {
  const AiSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<AiSection> {
  final _key = TextEditingController();
  bool _showKey = false;
  bool _busy = false;
  List<String>? _models;

  /// null = sin probar todavía; true = funciona; false = falló.
  bool? _keyWorks;
  String? _keyError;

  AppSettings get _settings => widget.settings;
  AiProvider get _provider => providerById(_settings.providerId);

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettings);
    // Al entrar se prueba sola la clave (no gasta saldo).
    if (_settings.hasKey(_provider.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _test(quiet: true);
      });
    }
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _key.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) return _snack('Pegá la clave primero.');
    if (!key.startsWith(_provider.keyPrefix)) {
      _snack(
        'Ojo: las claves de ${_provider.name} suelen empezar con "${_provider.keyPrefix}". Guardada igual.',
      );
    }
    await _settings.saveKey(_provider.id, key);
    _key.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await _test();
  }

  /// Prueba la clave pidiendo la lista de modelos (no gasta saldo).
  Future<void> _test({bool quiet = false}) async {
    final key = await _settings.keys.read(_provider.id);
    if (key == null) return _snack('Todavía no guardaste una clave.');
    setState(() => _busy = true);
    try {
      final models = await _provider.listModels(key);
      setState(() {
        _models = models;
        _keyWorks = true;
        _keyError = null;
      });
      final current =
          _settings.modelFor(_provider.id) ?? _provider.defaultModel;
      if (models.isNotEmpty && !models.contains(current)) {
        _snack(
          'Clave válida ✓, pero el modelo "$current" no está disponible. Elegí otro abajo.',
        );
      } else if (!quiet) {
        _snack('Clave válida ✓');
      }
    } on AiException catch (e) {
      setState(() {
        _keyWorks = false;
        _keyError = e.message;
      });
    } catch (_) {
      setState(() {
        _keyWorks = false;
        _keyError = 'No se pudo conectar. Revisá tu internet.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('¿Borrar la clave?'),
        content: Text(
          'Vas a borrar la clave de ${_provider.name} de este teléfono. '
          'Hasta que la vuelvas a cargar, el chat con IA no va a funcionar. '
          'Tu saldo y tu cuenta en ${_provider.name} no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, dejarla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _settings.deleteKey(_provider.id);
    setState(() {
      _models = null;
      _keyWorks = null;
      _keyError = null;
    });
    _snack('Clave borrada de este teléfono.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _provider;
    final hasKey = _settings.hasKey(provider.id);
    final model = _settings.modelFor(provider.id) ?? provider.defaultModel;
    // Primero los recomendados (con explicación), después el resto de la cuenta.
    final suggested = {for (final (id, d) in provider.suggestedModels) id: d};
    final others = ({...?_models, model}..removeAll(suggested.keys)).toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SettingsCard(
          title: 'Proveedor y clave',
          children: [
            DropdownButtonFormField<String>(
              initialValue: provider.id,
              decoration: const InputDecoration(labelText: 'Proveedor'),
              items: [
                for (final p in aiProviders)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _models = null;
                  _keyWorks = null;
                  _keyError = null;
                });
                _settings.setProvider(id);
              },
            ),
            if (hasKey)
              _KeyStatus(
                providerName: provider.name,
                works: _keyWorks,
                checking: _busy,
                error: _keyError,
                onTest: _busy ? null : _test,
                onDelete: _delete,
              )
            else
              Text(
                'Todavía no cargaste una clave de ${provider.name}.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            TextField(
              key: const Key('api-key'),
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: hasKey ? 'Reemplazar clave' : 'Pegá tu clave de API',
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Ocultar' : 'Mostrar',
                  icon: Icon(
                    _showKey ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar y probar'),
            ),
            Text(
              '🔒 La clave se guarda cifrada solo en este teléfono y se usa únicamente para hablar con ${provider.name}.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        SettingsCard(
          title: 'Modelo',
          children: [
            Text(
              'Tocá uno para elegirlo. Abajo de cada uno está para qué sirve '
              'y cuánto cuesta.',
              style: theme.textTheme.bodySmall,
            ),
            for (final id in suggested.keys)
              _ModelOption(
                id: id,
                description: suggested[id]!,
                selected: id == model,
                onTap: () => _settings.setModel(provider.id, id),
              ),
            if (others.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('other-${provider.id}-${others.length}-$model'),
                initialValue: others.contains(model) ? model : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Otros modelos de tu cuenta',
                  helperText: 'Sin explicación: solo si sabés cuál querés.',
                ),
                items: [
                  for (final m in others)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (m) {
                  if (m != null) _settings.setModel(provider.id, m);
                },
              )
            else if (_models == null && suggested.isEmpty)
              Text('Modelo: $model'),
          ],
        ),
        SettingsCard(
          title: 'Ayuda',
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              leading: const Icon(Icons.help_outline),
              title: Text('Cómo conseguir tu clave de ${provider.name}'),
              children: [
                for (final (i, step) in provider.guideSteps.indexed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                    title: Text(step),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir la página'),
                      onPressed: () => launchUrl(
                        Uri.parse(provider.keysUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar dirección'),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: provider.keysUrl),
                        );
                        _snack('Dirección copiada');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cada consulta a la IA gasta una fracción de centavo de tu saldo. '
                  'Las notificaciones, el listado y el almanaque no gastan nada.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Recuadro verde "funcionando", gris "probando" o rojo con el error.
class _KeyStatus extends StatelessWidget {
  const _KeyStatus({
    required this.providerName,
    required this.works,
    required this.checking,
    required this.error,
    required this.onTest,
    required this.onDelete,
  });

  final String providerName;
  final bool? works;
  final bool checking;
  final String? error;
  final VoidCallback? onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, bg, icon, title, detail) = switch ((checking, works)) {
      (true, _) => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
        Icons.hourglass_top,
        'Probando la clave…',
        'Clave guardada en este teléfono',
      ),
      (_, true) => (
        Colors.green.shade800,
        Colors.green.shade50,
        Icons.check_circle,
        'Conectado con $providerName ✓',
        'Clave guardada en este teléfono y funcionando',
      ),
      (_, false) => (
        theme.colorScheme.error,
        theme.colorScheme.errorContainer,
        Icons.error,
        'La clave no anda',
        error ?? 'Probá de nuevo o cargá otra.',
      ),
      _ => (
        Colors.green.shade800,
        Colors.green.shade50,
        Icons.lock,
        'Clave guardada',
        'Tocá "Probar" para ver si funciona',
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2, right: 8),
            child: Text(detail, style: theme.textTheme.bodySmall),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onTest, child: const Text('Probar')),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: onDelete,
                child: const Text('Borrar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un modelo recomendado: nombre, para qué sirve y cuánto sale.
class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.id,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colon = description.indexOf(':');
    final name = colon < 0 ? id : description.substring(0, colon);
    final text = colon < 0
        ? description
        : description.substring(colon + 1).trim();
    final price = priceFor(id);
    // Un recordatorio típico: unos 1000 tokens de entrada y 150 de salida.
    final per100 = price == null ? null : price.cost(1000, 150) * 100;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(text, style: theme.textTheme.bodySmall),
                    if (per100 != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '≈ US\$ ${per100.toStringAsFixed(per100 < 0.1 ? 3 : 2)} cada 100 recordatorios',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
