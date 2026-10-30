import 'dart:async';

import 'package:flutter/material.dart';

import '../calendar/calendar_screen.dart';
import '../chat/chat_screen.dart';
import '../notifications/reminder_actions_sheet.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_screen.dart';

/// Una pestaña de la barra inferior.
class AppTab {
  const AppTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
}

/// Lista de pestañas. Para sumar una nueva, agregala acá.
final List<AppTab> appTabs = [
  AppTab(
    label: 'Chat',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    builder: (_) => const ChatScreen(),
  ),
  AppTab(
    label: 'Almanaque',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    builder: (_) => const CalendarScreen(),
  ),
  AppTab(
    label: 'Listado',
    icon: Icons.checklist_outlined,
    selectedIcon: Icons.checklist,
    builder: (_) => const RemindersScreen(),
  ),
  AppTab(
    label: 'Configuración',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    builder: (_) => const SettingsScreen(),
  ),
];

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.openedReminders = const Stream.empty(),
    this.launchReminderId,
  });

  final Stream<int> openedReminders;
  final int? launchReminderId;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<int>? _openedSub;

  @override
  void initState() {
    super.initState();
    // Al tocar una notificación se muestran sus opciones (Hecho / Posponer).
    _openedSub = widget.openedReminders.listen(_showReminder);
    final launchId = widget.launchReminderId;
    if (launchId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showReminder(launchId),
      );
    }
  }

  @override
  void dispose() {
    _openedSub?.cancel();
    super.dispose();
  }

  void _showReminder(int id) {
    if (mounted) showReminderActionsSheet(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final tab = appTabs[_index];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recordame',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: tab.builder(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in appTabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
