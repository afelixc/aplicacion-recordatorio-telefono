import 'package:flutter/material.dart';

import '../home/coming_soon.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.settings_outlined,
      title: 'Configuración',
      description: 'Modo de uso, proveedor de IA, clave e instructivo. Llega en la etapa 5.',
    );
  }
}
