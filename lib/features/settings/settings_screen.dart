import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import 'notifications_section.dart';

/// Configuración. Por ahora solo la sección de notificaciones; en la etapa 5
/// se suman el modo de uso, el proveedor de IA, la clave y el instructivo.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = AppScope.of(context).notifications;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notifications != null)
          NotificationsSection(service: notifications)
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Las notificaciones solo funcionan en el teléfono.'),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Modo de uso, proveedor de IA, clave e instructivo: llegan en la etapa 5.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
