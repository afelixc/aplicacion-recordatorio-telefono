import 'package:flutter/material.dart';

import '../home/coming_soon.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.checklist_outlined,
      title: 'Listado',
      description: 'Todos tus recordatorios, para editar, borrar y marcar como hechos. Llega en la etapa 2.',
    );
  }
}
