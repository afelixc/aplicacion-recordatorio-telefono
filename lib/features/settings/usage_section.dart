import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../data/usage.dart';
import '../ai/ai_providers.dart';
import 'settings_screen.dart';

/// Resumen del consumo de un proveedor, calculado con el registro local.
class UsageSummary {
  UsageSummary(
    List<UsageRecord> all, {
    required DateTime now,
    (double, DateTime)? balance,
  }) : records = all {
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month);
    for (final r in all) {
      final cost = r.costUsd ?? 0;
      if (r.costUsd == null) hasUnknownCost = true;
      if (!r.at.isBefore(today)) {
        todayCost += cost;
        todayCount++;
      }
      if (!r.at.isBefore(monthStart)) {
        monthCost += cost;
        monthCount++;
      }
      if (balance != null && !r.at.isBefore(balance.$2)) {
        spentSinceBalance += cost;
      }
    }
    remaining = balance == null ? null : balance.$1 - spentSinceBalance;
    for (var i = 13; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day - i);
      final next = DateTime(day.year, day.month, day.day + 1);
      final ofDay = all.where(
        (r) => !r.at.isBefore(day) && r.at.isBefore(next),
      );
      days.add(
        DayUsage(
          day,
          ofDay.fold(0.0, (sum, r) => sum + (r.costUsd ?? 0)),
          ofDay.length,
        ),
      );
    }
  }

  final List<UsageRecord> records;
  double todayCost = 0;
  int todayCount = 0;
  double monthCost = 0;
  int monthCount = 0;
  double spentSinceBalance = 0;
  double? remaining;
  bool hasUnknownCost = false;

  /// Los últimos 14 días, del más viejo a hoy.
  final List<DayUsage> days = [];
}

class DayUsage {
  const DayUsage(this.day, this.cost, this.count);

  final DateTime day;
  final double cost;
  final int count;
}

/// Dólares con los decimales justos: los consumos chicos llevan 4.
String usd(double v) => v.abs() < 0.01 && v != 0
    ? 'US\$ ${v.toStringAsFixed(4)}'
    : 'US\$ ${v.toStringAsFixed(2)}';

/// Consumo de IA: hoy, este mes, saldo estimado y gráfico por día.
class UsageSection extends StatefulWidget {
  const UsageSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<UsageSection> createState() => _UsageSectionState();
}

class _UsageSectionState extends State<UsageSection>
    with WidgetsBindingObserver {
  AppSettings get settings => widget.settings;

  /// Se fue a la página del proveedor: al volver, preguntar el saldo.
  bool _wentToBillingPage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wentToBillingPage) {
      _wentToBillingPage = false;
      _askBalance(context, title: '¿Cuánto saldo te figura ahora?');
    }
  }

  Future<void> _openBillingPage(String url) async {
    _wentToBillingPage = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _askBalance(
    BuildContext context, {
    String title = '¿Cuánto saldo tenés?',
  }) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anotá el saldo que ves en la página del proveedor, en dólares. '
              'Desde ahora la app te va restando lo que vas consumiendo. '
              'Si no lo viste, tocá Cancelar.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('balance-input'),
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                prefixText: 'US\$ ',
                hintText: '5.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (amount != null) await settings.setBalance(settings.providerId, amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = providerById(settings.providerId);
    final balance = settings.balanceFor(provider.id);
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, now.day - 13);
    final monthStart = DateTime(now.year, now.month);
    if (monthStart.isBefore(from)) from = monthStart;
    if (balance != null && balance.$2.isBefore(from)) from = balance.$2;

    return StreamBuilder<List<UsageRecord>>(
      stream: AppScope.of(context).usage.watchSince(from),
      builder: (context, snapshot) {
        final summary = UsageSummary(
          [
            for (final r in snapshot.data ?? const <UsageRecord>[])
              if (r.provider == provider.id) r,
          ],
          now: now,
          balance: balance,
        );
        final showCost = !summary.hasUnknownCost;
        return SettingsCard(
          title: 'Consumo de IA · ${provider.name}',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Hoy',
                    value: showCost
                        ? usd(summary.todayCost)
                        : '${summary.todayCount}',
                    detail: '${summary.todayCount} consultas',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Este mes',
                    value: showCost
                        ? usd(summary.monthCost)
                        : '${summary.monthCount}',
                    detail: '${summary.monthCount} consultas',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Saldo estimado',
                    value: summary.remaining == null
                        ? '—'
                        : usd(summary.remaining!),
                    detail: balance == null
                        ? 'Anotá tu saldo'
                        : 'desde el ${DateFormat('d/M', Fmt.locale).format(balance.$2)}',
                    warn: summary.remaining != null && summary.remaining! < 0.5,
                  ),
                ),
              ],
            ),
            Text(
              showCost
                  ? 'Gasto por día (últimos 14 días)'
                  : 'Consultas por día (últimos 14 días)',
              style: theme.textTheme.labelLarge,
            ),
            UsageBars(days: summary.days, showCost: showCost),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: Text(
                    balance == null ? 'Anotar saldo' : 'Actualizar saldo',
                  ),
                  onPressed: () => _askBalance(context),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver o cargar saldo'),
                  onPressed: () => _openBillingPage(provider.billingUrl),
                ),
              ],
            ),
            Text(
              showCost
                  ? 'Es un cálculo de la app con el precio de cada modelo; puede diferir un poco del real. '
                        'Con "Ver o cargar saldo" vas a la página de ${provider.name} y, al volver, '
                        'la app te pregunta el saldo que te figura para quedar al día.'
                  : 'No conozco el precio del modelo que usás, así que muestro cantidad de consultas. '
                        'El gasto exacto y la carga de saldo están en la página de ${provider.name}.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.detail,
    this.warn = false,
  });

  final String label;
  final String value;
  final String detail;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (warn) ...[
              Icon(
                Icons.warning_amber,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(detail, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Barras por día: una sola serie, un solo color, la punta redondeada.
/// Tocando una barra se ve el detalle de ese día.
class UsageBars extends StatelessWidget {
  const UsageBars({super.key, required this.days, required this.showCost});

  final List<DayUsage> days;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    double value(DayUsage d) => showCost ? d.cost : d.count.toDouble();
    final max = days.map(value).fold(0.0, (a, b) => a > b ? a : b);
    final dayFmt = DateFormat('d/M', Fmt.locale);
    const chartHeight = 96.0;

    if (max == 0) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'Todavía no hay consultas en estos días.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'máx. ${showCost ? usd(max) : '${max.toInt()} consultas'}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message:
                        '${DateFormat("EEE d/M", Fmt.locale).format(d.day)}\n'
                        '${showCost ? '${usd(d.cost)} · ' : ''}${d.count} consultas',
                    child: Semantics(
                      label:
                          '${dayFmt.format(d.day)}: ${showCost ? usd(d.cost) : '${d.count} consultas'}',
                      child: Container(
                        // Zona para tocar más grande que la barra.
                        height: chartHeight,
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: value(d) == 0
                              ? 0
                              : (value(d) / max * chartHeight).clamp(
                                  3,
                                  chartHeight,
                                ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final d in [days.first, days[days.length ~/ 2], days.last])
              Text(
                d == days.last ? 'hoy' : dayFmt.format(d.day),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
