import 'package:flutter/material.dart';

import '../home/coming_soon.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.calendar_month_outlined,
      title: 'Almanaque',
      description: 'Calendario mensual con tus recordatorios. Llega en la etapa 4.',
    );
  }
}
