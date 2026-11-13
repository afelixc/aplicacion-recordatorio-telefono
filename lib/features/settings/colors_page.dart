import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/palette.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';

/// Cambia el ícono del teléfono (activity-alias en `MainActivity.kt`).
class AppIconChanger {
  static const _channel = MethodChannel('recordame/icono');

  /// true si Android lo cambió.
  static Future<bool> change(String id) async {
    try {
      return await _channel.invokeMethod<bool>('cambiar', {'id': id}) ?? false;
    } catch (_) {
      return false; // Vista web o pruebas: no hay ícono para cambiar.
    }
  }
}

/// Configuración → Colores: día/noche, ícono, y los colores de la app, el
/// almanaque y el listado (por separado para el día y la noche).
class ColorsPage extends StatefulWidget {
  const ColorsPage({super.key, this.startAtNight = false});

  /// Abrir directamente en la solapa de noche.
  final bool startAtNight;

  @override
  State<ColorsPage> createState() => _ColorsPageState();
}

class _ColorsPageState extends State<ColorsPage> {
  late bool _night = widget.startAtNight;

  Future<void> _pickIcon(AppSettings settings, AppIcon icon) async {
    if (icon.id == settings.appIconId) return;
    final messenger = ScaffoldMessenger.of(context);
    await settings.setAppIcon(icon.id);
    final ok = await AppIconChanger.change(icon.id);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        showCloseIcon: true,
        content: Text(
          ok
              ? 'Listo, ícono ${icon.name}. Puede tardar unos segundos en '
                    'cambiar. Si desaparece de la pantalla de inicio, buscalo '
                    'entre todas las apps y volvé a ponerlo.'
              : 'Elegido el ícono ${icon.name}. Se cambia en el teléfono.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Colores')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final c = settings.colorsFor(night: _night);
          void set(ColorSet v) => settings.setColors(v, night: _night);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Box(
                title: 'Día y noche',
                icon: Icons.brightness_6_outlined,
                children: [
                  SegmentedButton<DayNight>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: DayNight.auto,
                        label: Text('Como el teléfono'),
                      ),
                      ButtonSegment(
                        value: DayNight.day,
                        label: Text('Siempre día'),
                      ),
                      ButtonSegment(
                        value: DayNight.night,
                        label: Text('Siempre noche'),
                      ),
                    ],
                    selected: {settings.dayNight},
                    onSelectionChanged: (v) {
                      settings.setDayNight(v.first);
                      if (v.first != DayNight.auto) {
                        setState(() => _night = v.first == DayNight.night);
                      }
                    },
                  ),
                  Text(switch (settings.dayNight) {
                    DayNight.auto =>
                      'Cambia sola cuando el teléfono pasa a modo oscuro.',
                    DayNight.day => 'Siempre con los colores de día.',
                    DayNight.night => 'Siempre con los colores de noche.',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 14),
              _Box(
                title: 'Ícono del teléfono',
                icon: Icons.apps,
                children: [
                  Text(
                    'El dibujito de Recordame en la pantalla de inicio. '
                    'Elegís uno de estos, ya vienen preparados. Es uno solo '
                    'para día y noche.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final icon in appIcons)
                        Tooltip(
                          message: icon.name,
                          child: InkWell(
                            key: Key('icon-${icon.id}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _pickIcon(settings, icon),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  width: 3,
                                  color: icon.id == settings.appIconId
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                ),
                              ),
                              child: AppIconPreview(icon, size: 46),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'Elegido: ${appIcon(settings.appIconId).name}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DayNightTabs(
                night: _night,
                onChanged: (v) {
                  setState(() => _night = v);
                  if (settings.dayNight != DayNight.auto) {
                    settings.setDayNight(v ? DayNight.night : DayNight.day);
                  }
                },
              ),
              // La zona usa el tema del modo que se está pintando: sirve de
              // muestra en vivo (de día se ve de día, aunque sea de noche).
              Theme(
                data: _night ? AppTheme.dark(c) : AppTheme.light(c),
                child: _Zone(
                  night: _night,
                  children: [
                    _Box(
                      title: 'Fondo',
                      icon: Icons.wallpaper,
                      children: [
                        _BackgroundRow(
                          selected: c.background,
                          night: _night,
                          onPick: (id) => set(c.copyWith(background: id)),
                        ),
                      ],
                    ),
                    _Box(
                      title: 'La app',
                      icon: Icons.phone_android,
                      children: [
                        const _Hint('Barra de arriba, botones y "Nuevo".'),
                        _StrongRow(
                          label: 'Color principal',
                          prefix: 'main',
                          options: mainColors,
                          selected: c.main,
                          night: _night,
                          onPick: (id) => set(c.copyWith(main: id)),
                        ),
                        const _Hint('Muestra (no se toca):'),
                        _AppSample(color: mainColor(c.main), night: _night),
                      ],
                    ),
                    _Box(
                      title: 'Almanaque',
                      icon: Icons.calendar_month,
                      children: [
                        _StrongRow(
                          label: 'Hoy',
                          prefix: 'today',
                          options: todayColors,
                          selected: c.today,
                          night: _night,
                          onPick: (id) => set(c.copyWith(today: id)),
                        ),
                        _SoftRow(
                          label: 'Días con recordatorios',
                          prefix: 'has',
                          selected: c.withReminders,
                          night: _night,
                          onPick: (id) => set(c.copyWith(withReminders: id)),
                        ),
                        _StrongRow(
                          label: 'Día que tocaste (borde)',
                          prefix: 'sel',
                          options: mainColors,
                          selected: c.selected,
                          night: _night,
                          onPick: (id) => set(c.copyWith(selected: id)),
                        ),
                        _CalendarSample(colors: c, night: _night),
                      ],
                    ),
                    _Box(
                      title: 'Listado',
                      icon: Icons.list,
                      note: 'solapa Todos',
                      children: [
                        _SoftRow(
                          label: 'Los que faltan hacer',
                          prefix: 'pend',
                          selected: c.pending,
                          night: _night,
                          onPick: (id) => set(c.copyWith(pending: id)),
                        ),
                        _SoftRow(
                          label: 'Los hechos',
                          prefix: 'done',
                          selected: c.done,
                          night: _night,
                          onPick: (id) => set(c.copyWith(done: id)),
                        ),
                        _ListSample(colors: c, night: _night),
                      ],
                    ),
                    _Box(
                      title: 'Libreta',
                      icon: Icons.menu_book_outlined,
                      note: 'adentro de las carpetas',
                      children: [
                        _SoftRow(
                          label: 'Las que faltan hacer',
                          prefix: 'lpend',
                          selected: c.notePending,
                          night: _night,
                          onPick: (id) => set(c.copyWith(notePending: id)),
                        ),
                        _SoftRow(
                          label: 'Las hechas',
                          prefix: 'ldone',
                          selected: c.noteDone,
                          night: _night,
                          onPick: (id) => set(c.copyWith(noteDone: id)),
                        ),
                        _ListSample(
                          colors: c.copyWith(
                            pending: c.notePending,
                            done: c.noteDone,
                          ),
                          night: _night,
                          pendingText: 'Comprar vino',
                          doneText: 'Cambiar el tóner',
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => set(const ColorSet()),
                          child: Text(
                            'Volver a los de siempre '
                            '(${_night ? 'noche' : 'día'})',
                          ),
                        ),
                        TextButton(
                          onPressed: () => _night
                              ? settings.setColors(
                                  settings.dayColors,
                                  night: true,
                                )
                              : settings.setColors(c, night: true),
                          child: Text(
                            _night
                                ? 'Copiar los de día'
                                : 'Usar estos mismos de noche',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Las dos solapas grandes: colores de día / de noche.
class _DayNightTabs extends StatelessWidget {
  const _DayNightTabs({required this.night, required this.onChanged});

  final bool night;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(bool isNight) {
      final on = night == isNight;
      final bg = isNight ? const Color(0xFF1B2140) : const Color(0xFFFFF6DC);
      final fg = isNight ? const Color(0xFFE3E8FF) : const Color(0xFF7A5300);
      final line = isNight ? const Color(0xFF3A4470) : const Color(0xFFE8C77A);
      return Expanded(
        child: Opacity(
          opacity: on ? 1 : 0.55,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              side: BorderSide(color: line, width: 2),
            ),
            child: InkWell(
              key: Key(isNight ? 'edit-night' : 'edit-day'),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              onTap: () => onChanged(isNight),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isNight ? Icons.dark_mode : Icons.light_mode,
                      color: fg,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isNight ? 'Colores de NOCHE' : 'Colores de DÍA',
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [tab(false), const SizedBox(width: 6), tab(true)]);
  }
}

/// Zona de un modo: borde grueso de su color y los recuadros adentro.
class _Zone extends StatelessWidget {
  const _Zone({required this.night, required this.children});

  final bool night;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = night ? const Color(0xFF3A4470) : const Color(0xFFE8C77A);
    final fg = night ? const Color(0xFFC9D2FF) : const Color(0xFF7A5300);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: line, width: 3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              night
                  ? 'ESTÁS PINTANDO LOS COLORES DE NOCHE'
                  : 'ESTÁS PINTANDO LOS COLORES DE DÍA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (final w in children) ...[w, const SizedBox(height: 12)],
        ],
      ),
    );
  }
}

/// Recuadro con título grande en una franja de color.
class _Box extends StatelessWidget {
  const _Box({
    required this.title,
    required this.icon,
    required this.children,
    this.note,
  });

  final String title;
  final IconData icon;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outline, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              border: Border(
                bottom: BorderSide(color: scheme.outline, width: 2),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                if (note != null) ...[
                  const Spacer(),
                  Text(
                    note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in children) ...[w, const SizedBox(height: 10)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).hintColor),
  );
}

/// Un círculo de color para tocar.
class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.name,
    required this.fill,
    required this.border,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color fill;
  final Color border;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = fill.computeLuminance() > 0.5;
    return Tooltip(
      message: name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : border,
              width: selected ? 3.5 : 2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: light ? Colors.black87 : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _StrongRow extends StatelessWidget {
  const _StrongRow({
    required this.label,
    required this.prefix,
    required this.options,
    required this.selected,
    required this.night,
    required this.onPick,
  });

  final String label;
  final String prefix;
  final List<StrongColor> options;
  final String selected;
  final bool night;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final o in options)
            _Dot(
              key: Key('$prefix-${o.id}'),
              name: o.name,
              fill: o.of(night),
              border: o.of(night),
              selected: o.id == selected,
              onTap: () => onPick(o.id),
            ),
        ],
      ),
    ],
  );
}

class _SoftRow extends StatelessWidget {
  const _SoftRow({
    required this.label,
    required this.prefix,
    required this.selected,
    required this.night,
    required this.onPick,
  });

  final String label;
  final String prefix;
  final String selected;
  final bool night;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final o in softColors)
            _Dot(
              key: Key('$prefix-${o.id}'),
              name: o.name,
              fill: o.fill(night),
              border: o.border(night),
              selected: o.id == selected,
              onTap: () => onPick(o.id),
            ),
        ],
      ),
    ],
  );
}

/// Fondos sutiles: cuadraditos con el nombre abajo.
class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({
    required this.selected,
    required this.night,
    required this.onPick,
  });

  final String selected;
  final bool night;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final b in backgroundColors)
          InkWell(
            key: Key('bg-${b.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPick(b.id),
            child: SizedBox(
              width: 66,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 40,
                    decoration: BoxDecoration(
                      color: b.of(night),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: b.id == selected
                            ? scheme.primary
                            : scheme.outline,
                        width: b.id == selected ? 3.5 : 1.5,
                      ),
                    ),
                    child: b.id == selected
                        ? Icon(Icons.check, color: scheme.primary)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.id == 'normal'
                        ? (night ? 'Azul oscuro' : 'Blanco')
                        : b.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: b.id == selected ? FontWeight.w800 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Muestra: la barra de arriba y el botón "Nuevo".
class _AppSample extends StatelessWidget {
  const _AppSample({required this.color, required this.night});

  final StrongColor color;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: night ? scheme.surfaceContainer : scheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              'TE RECORDARÉ',
              style: TextStyle(
                color: night ? scheme.primary : scheme.onPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Nuevo'),
        ),
      ],
    );
  }
}

/// Muestra: hoy, un día con recordatorios y el día elegido.
class _CalendarSample extends StatelessWidget {
  const _CalendarSample({required this.colors, required this.night});

  final ColorSet colors;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String n, String label, {Color? bg, Color? line, Color? fg}) =>
        Column(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: line ?? Colors.transparent, width: 2),
              ),
              child: Text(
                n,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: fg ?? scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        cell(
          '3',
          'Hoy',
          bg: todayColor(colors.today).of(night),
          fg: night ? const Color(0xFF10131C) : Colors.white,
        ),
        cell(
          '12',
          'Con recordatorios',
          bg: softColor(colors.withReminders).fill(night),
        ),
        cell(
          '20',
          'El que tocaste',
          line: mainColor(colors.selected).of(night),
        ),
      ],
    );
  }
}

/// Muestra: un pendiente y un hecho.
class _ListSample extends StatelessWidget {
  const _ListSample({
    required this.colors,
    required this.night,
    this.pendingText = 'Llamar al dentista',
    this.doneText = 'Pagar la luz',
  });

  final ColorSet colors;
  final bool night;
  final String pendingText;
  final String doneText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String text, SoftColor c, bool done) => Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.fill(night),
        border: Border.all(color: c.border(night)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: done ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: done
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: scheme.onSurfaceVariant,
                    )
                  : const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile(pendingText, softColor(colors.pending), false),
        tile(doneText, softColor(colors.done), true),
      ],
    );
  }
}

/// Dibujo del ícono de Recordame (libreta con campanita) con los colores
/// de una combinación. Es el mismo dibujo que `tool/generar_iconos.py`.
class AppIconPreview extends StatelessWidget {
  const AppIconPreview(this.icon, {super.key, this.size = 48});

  final AppIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.22),
      border: icon.id == 'blanco'
          ? Border.all(color: const Color(0xFFD7DBE5))
          : null,
    ),
    child: CustomPaint(painter: _LogoPainter(icon)),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.icon);

  final AppIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    final f = size.width / 108;
    canvas.scale(f);
    final bg = icon.background;
    final book = icon.bell;
    // Espiral blanca (en el de fondo blanco, del color de la libreta);
    // campanita blanca salvo que la libreta sea muy clara.
    final ring = bg.computeLuminance() > 0.8 ? book : Colors.white;
    final det = book.computeLuminance() > 0.5 ? bg : Colors.white;
    RRect box(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
    canvas.drawRRect(box(0, 0, 108, 108, 108 * 0.22), Paint()..color = bg);
    canvas.drawRRect(box(28, 20, 54, 70, 8), Paint()..color = book);
    for (final y in [30.0, 42.0, 54.0, 66.0, 78.0]) {
      canvas.drawRRect(box(22, y - 3, 14, 6, 3), Paint()..color = ring);
    }
    final bell = Path()
      ..moveTo(57, 36)
      ..cubicTo(49, 36, 44, 42, 44, 50)
      ..lineTo(44, 57)
      ..lineTo(40, 63)
      ..lineTo(74, 63)
      ..lineTo(70, 57)
      ..lineTo(70, 50)
      ..cubicTo(70, 42, 65, 36, 57, 36)
      ..close();
    canvas.drawPath(bell, Paint()..color = det);
    canvas.drawCircle(const Offset(57, 68), 4.5, Paint()..color = det);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.icon != icon;
}
