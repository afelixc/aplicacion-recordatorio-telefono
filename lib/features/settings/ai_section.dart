import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_providers.dart';
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

  AppSettings get _settings => widget.settings;
  AiProvider get _provider => providerById(_settings.providerId);

  @override
  void dispose() {
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
  Future<void> _test() async {
    final key = await _settings.keys.read(_provider.id);
    if (key == null) return _snack('Todavía no guardaste una clave.');
    setState(() => _busy = true);
    try {
      final models = await _provider.listModels(key);
      setState(() => _models = models);
      final current =
          _settings.modelFor(_provider.id) ?? _provider.defaultModel;
      if (models.isNotEmpty && !models.contains(current)) {
        _snack(
          'Clave válida ✓, pero el modelo "$current" no está disponible. Elegí otro abajo.',
        );
      } else {
        _snack('Clave válida ✓');
      }
    } on AiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo conectar. Revisá tu internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    await _settings.deleteKey(_provider.id);
    setState(() => _models = null);
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
    final modelOptions = [...suggested.keys, ...others];
    String shortName(String id) {
      final d = suggested[id];
      return d == null ? id : d.split(':').first;
    }

    return SettingsCard(
      title: 'Inteligencia artificial',
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
            setState(() => _models = null);
            _settings.setProvider(id);
          },
        ),
        if (hasKey)
          Row(
            children: [
              const Icon(Icons.lock, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Clave guardada en este teléfono')),
              TextButton(
                onPressed: _busy ? null : _test,
                child: const Text('Probar'),
              ),
              TextButton(onPressed: _delete, child: const Text('Borrar')),
            ],
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
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
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
        DropdownButtonFormField<String>(
          key: ValueKey('model-${provider.id}-${modelOptions.length}'),
          initialValue: model,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Modelo',
            helperMaxLines: 3,
            helperText:
                suggested[model] ??
                (_models == null
                    ? 'Tocá "Probar" para ver todos los modelos de tu cuenta.'
                    : null),
          ),
          items: [
            for (final m in modelOptions)
              DropdownMenuItem(
                value: m,
                child: Text(shortName(m), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (m) {
            if (m != null) _settings.setModel(provider.id, m);
          },
        ),
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
                    Clipboard.setData(ClipboardData(text: provider.keysUrl));
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
    );
  }
}
