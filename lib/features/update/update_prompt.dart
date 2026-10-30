import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import 'update_service.dart';

/// Al abrir la app, si hay una versión nueva en GitHub, pregunta si se quiere
/// actualizar. Si el usuario acepta, baja el APK y abre el instalador de Android.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({super.key, required this.child, this.service});

  final Widget child;
  final UpdateService? service;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  @override
  void initState() {
    super.initState();
    // Solo tiene sentido en el teléfono: en la vista web no hay APK que instalar.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final release = await (widget.service ?? UpdateService()).checkForUpdate();
    if (release == null || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Hay una versión nueva'),
        content: const Text(
          'Se bajó una versión nueva de Recordame. '
          'Tus recordatorios no se pierden al actualizar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) _install(release);
  }

  void _install(AppRelease release) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Bajando la versión nueva…')),
    );
    OtaUpdate()
        .execute(release.apkUrl, destinationFilename: UpdateService.apkName)
        .listen(
          (event) {
            if (event.status == OtaStatus.INSTALLING) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Tocá "Actualizar" en la ventana de Android.'),
                ),
              );
            } else if (event.status != OtaStatus.DOWNLOADING &&
                event.status != OtaStatus.INSTALLATION_DONE) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR
                        ? 'Permití que Recordame instale apps y probá de nuevo.'
                        : 'No se pudo bajar la actualización. Probá más tarde.',
                  ),
                ),
              );
            }
          },
          onError: (_) => messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo bajar la actualización. Probá más tarde.',
              ),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
