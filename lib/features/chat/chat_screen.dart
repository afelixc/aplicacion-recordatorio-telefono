import 'package:flutter/material.dart';

import '../home/coming_soon.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.chat_bubble_outline,
      title: 'Chat',
      description: 'Acá vas a escribir o hablar para crear recordatorios. Llega en las etapas 6 y 7.',
    );
  }
}
