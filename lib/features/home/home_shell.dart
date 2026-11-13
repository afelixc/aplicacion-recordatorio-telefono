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

  /// Cambia de pestaña desde cualquier pantalla (por ejemplo, ir a Configuración).
  static void goToTab(BuildContext context, String label) {
    final state = context.findAncestorStateOfType<_HomeShellState>();
    final index = appTabs.indexWhere((t) => t.label == label);
    if (state != null && index >= 0) state._select(index);
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);
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
    final scheme = Theme.of(context).colorScheme;
    final night = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        // Barra con el color de la app (Configuración → Colores). De noche,
        // fondo oscuro y letras de ese color, para que no encandile.
        backgroundColor: night ? scheme.surfaceContainer : scheme.primary,
        foregroundColor: night ? scheme.primary : scheme.onPrimary,
        centerTitle: true,
        title: const Text(
          'TE RECORDARÉ',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
      ),
      body: tab.builder(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final t in appTabs)
            _OneLineLabel(
              label: t.label,
              child: NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
            ),
        ],
      ),
    );
  }
}

/// Si el nombre de la solapa no entra en un renglón (p. ej. "Configuración"
/// con letra grande), achica solo esa palabra para que entre, y el dibujo
/// queda a la misma altura que los demás (pedido del usuario).
class _OneLineLabel extends StatelessWidget {
  const _OneLineLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (theme.navigationBarTheme.labelTextStyle?.resolve({
                  WidgetState.selected,
                }) ??
                theme.textTheme.labelMedium)!
            .copyWith(fontWeight: FontWeight.w700);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final room = box.maxWidth - 8;
        final width = painter.width;
        painter.dispose();
        if (width <= room) return child;
        final size = style.fontSize ?? 12;
        final fitted = scaler.scale(size) * room / width;
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fitted / size)),
          child: child,
        );
      },
    );
  }
}
