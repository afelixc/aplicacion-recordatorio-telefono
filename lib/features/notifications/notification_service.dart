import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/formatting.dart';
import '../../data/drift/database.dart';
import '../../data/drift/drift_reminder_repository.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import '../../data/scheduling_reminder_repository.dart';
import 'notification_sound.dart';
import 'reminder_actions.dart';
import 'reminder_scheduler.dart';
import 'snooze_options.dart';

/// Estado de los permisos y avisos, para la sección de diagnóstico.
class NotificationStatus {
  const NotificationStatus({
    required this.enabled,
    required this.exactAlarms,
    required this.pending,
    required this.timeZone,
    this.lastError,
  });

  final bool enabled;
  final bool exactAlarms;
  final int pending;
  final String timeZone;
  final String? lastError;
}

/// Notificaciones locales de Android. Funcionan sin internet, con la app
/// cerrada y después de reiniciar el teléfono (el plugin las vuelve a programar).
class NotificationService implements ReminderScheduler {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Recordatorios tocados en la notificación, para que la app muestre sus opciones.
  final _opened = StreamController<int>.broadcast();
  Stream<int> get openedReminders => _opened.stream;

  /// Recordatorio que abrió la app al tocar su notificación (con la app cerrada).
  int? launchReminderId;

  /// Se asigna en main(): ejecuta los botones cuando la app está abierta.
  ReminderActions? foregroundActions;

  /// Android no deja cambiar el sonido de un canal ya creado: cada sonido
  /// nuevo usa un canal nuevo (`recordatorios_<n>`) y se borra el anterior.
  static const _defaultChannelId = 'recordatorios';
  String _channelId = _defaultChannelId;
  String? _soundUri;
  String _soundName = builtInSounds.first.name;

  String? get soundUri => _soundUri;
  String get soundName => _soundName;

  AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    _channelId,
    'Recordatorios',
    description: 'Avisos de tus recordatorios a la hora indicada',
    importance: Importance.high,
    sound: _soundUri == null ? null : UriAndroidNotificationSound(_soundUri!),
  );

  /// Lee el sonido elegido (también desde los botones con la app cerrada).
  Future<void> loadSound() async {
    final p = await SharedPreferences.getInstance();
    _channelId = p.getString('notif_channel') ?? _defaultChannelId;
    _soundUri = p.getString('notif_sound_uri');
    _soundName = p.getString('notif_sound_name') ?? builtInSounds.first.name;
  }

  /// Cambia el sonido de los avisos. Después hay que volver a programar los
  /// avisos (`resync`) para que usen el canal nuevo.
  Future<void> setSound(SoundChoice choice) async {
    final old = _channelId;
    _soundUri = choice.uri;
    _soundName = choice.name;
    _channelId = 'recordatorios_${DateTime.now().millisecondsSinceEpoch}';
    await _android?.createNotificationChannel(_channel);
    if (old != _channelId) {
      await _android?.deleteNotificationChannel(channelId: old);
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('notif_channel', _channelId);
    await p.setString('notif_sound_name', _soundName);
    if (_soundUri == null) {
      await p.remove('notif_sound_uri');
    } else {
      await p.setString('notif_sound_uri', _soundUri!);
    }
  }

  Future<void> init() async {
    await _initTimeZone();
    await loadSound();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );
    await _android?.createNotificationChannel(_channel);

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) launchReminderId = reminderIdOf(response);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Último error al programar un aviso (se muestra en Configuración).
  String? lastError;

  static const _package = 'com.afelixc.recordame';

  Future<NotificationStatus> status() async => NotificationStatus(
    enabled: await _android?.areNotificationsEnabled() ?? false,
    exactAlarms: await _android?.canScheduleExactNotifications() ?? false,
    pending: (await _plugin.pendingNotificationRequests()).length,
    timeZone: tz.local.name,
    lastError: lastError,
  );

  /// Muestra un aviso de prueba ahora mismo.
  Future<void> showTest() => _plugin.show(
    id: 0,
    title: 'Aviso de prueba',
    body: 'Si ves esto, las notificaciones funcionan.',
    notificationDetails: _details(),
  );

  /// Programa un aviso de prueba para dentro de [delay].
  Future<void> scheduleTest(Duration delay) async {
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: 0,
      title: 'Aviso de prueba programado',
      body: 'Llegó a horario. Las notificaciones programadas funcionan.',
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _details(),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> requestExactAlarms() async =>
      _android?.requestExactAlarmsPermission();

  /// Abre los ajustes de notificaciones de la app.
  Future<void> openNotificationSettings() => const AndroidIntent(
    action: 'android.settings.APP_NOTIFICATION_SETTINGS',
    arguments: {'android.provider.extra.APP_PACKAGE': _package},
  ).launch();

  /// Pide que Android no cierre la app para ahorrar batería.
  Future<void> openBatterySettings() async {
    try {
      await const AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$_package',
      ).launch();
    } catch (_) {
      await const AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      ).launch();
    }
  }

  /// Pide permiso para mostrar notificaciones (Android 13 en adelante).
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  Future<void> _onResponse(NotificationResponse response) async {
    final id = reminderIdOf(response);
    if (id == null) return;
    final handled =
        await foregroundActions?.handle(id, response.actionId) ?? false;
    if (!handled) _opened.add(id);
  }

  static Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Argentina/Buenos_Aires'));
    }
  }

  NotificationDetails _details() => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      sound: _channel.sound,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      color: const Color(0xFF2B3A67),
      actions: [
        const AndroidNotificationAction(ReminderActions.doneActionId, 'Hecho'),
        for (final o in snoozeOptions.where((o) => o.showInNotification))
          AndroidNotificationAction(o.id, o.label),
      ],
    ),
  );

  /// Cada recordatorio usa los números de aviso `id * 100` a `id * 100 + 99`:
  /// uno por cada día de la semana o fecha suelta, y el último para "Posponer".
  static const _slots = 100;
  static const _snoozeSlot = 99;

  /// Recordatorio al que pertenece un aviso.
  static int? reminderIdOf(NotificationResponse response) =>
      int.tryParse(response.payload ?? '') ??
      (response.id == null ? null : response.id! ~/ _slots);

  @override
  Future<void> schedule(Reminder reminder) async {
    final id = reminder.id;
    if (id == null) return;
    await cancel(id);
    await _schedule(reminder);
  }

  Future<void> _schedule(Reminder reminder) async {
    final id = reminder.id!;
    if (reminder.done) return;
    final now = DateTime.now();
    final start = reminder.dueAt;
    final rule = reminder.recurrence;

    try {
      final exact = await _android?.canScheduleExactNotifications() ?? true;
      Future<void> at(int slot, DateTime when, [DateTimeComponents? repeat]) =>
          _plugin.zonedSchedule(
            id: id * _slots + slot,
            title: reminder.title,
            body: 'Recordatorio · ${Fmt.time(when)} h',
            scheduledDate: tz.TZDateTime.from(when, tz.local),
            notificationDetails: _details(),
            androidScheduleMode: exact
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: repeat,
            payload: '$id',
          );

      switch (rule.kind) {
        case RepeatKind.none:
          if (start.isAfter(now)) await at(0, start);
        case RepeatKind.daily:
          await at(0, rule.nextAfter(start, now)!, DateTimeComponents.time);
        case RepeatKind.weekly:
          // Un aviso que se repite por cada día de la semana elegido.
          final days =
              (rule.weekdays.isEmpty ? {start.weekday} : rule.weekdays).toList()
                ..sort();
          for (var i = 0; i < days.length; i++) {
            final next = Recurrence.weekly({days[i]}).nextAfter(start, now)!;
            await at(i, next, DateTimeComponents.dayOfWeekAndTime);
          }
        case RepeatKind.yearly:
          await at(
            0,
            rule.nextAfter(start, now)!,
            DateTimeComponents.dateAndTime,
          );
        case RepeatKind.monthly:
        case RepeatKind.dates:
          // Los meses no tienen todos los mismos días: se programan uno por uno
          // (se completan de nuevo cada vez que se abre la app).
          final dates = rule.upcoming(start, now, 24);
          for (var i = 0; i < dates.length; i++) {
            await at(i, dates[i]);
          }
      }

      final snoozed = reminder.snoozedUntil;
      if (snoozed != null && snoozed.isAfter(now)) {
        await at(_snoozeSlot, snoozed);
      }
      lastError = null;
    } catch (e) {
      // El recordatorio queda guardado igual; el error se ve en Configuración.
      lastError = '$e';
      debugPrint('No se pudo programar el aviso $id: $e');
    }
  }

  @override
  Future<void> cancel(int reminderId) async {
    for (final p in await _plugin.pendingNotificationRequests()) {
      // `p.id == reminderId`: avisos de la versión 1.0.5 o anterior.
      if (p.id ~/ _slots == reminderId || p.id == reminderId) {
        await _plugin.cancel(id: p.id);
      }
    }
  }

  @override
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    await _plugin.cancelAll();
    for (final r in reminders) {
      if (r.id != null) await _schedule(r);
    }
  }
}

/// Botones de la notificación tocados con la app cerrada. Android lo ejecuta
/// aparte de la app, así que abre su propia conexión a la base.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  final id = NotificationService.reminderIdOf(response);
  if (id == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(Fmt.locale);
  await NotificationService._initTimeZone();
  await NotificationService.instance.loadSound();
  final db = AppDatabase();
  try {
    final repo = SchedulingReminderRepository(
      DriftReminderRepository(db),
      NotificationService.instance,
    );
    await ReminderActions(repo).handle(id, response.actionId);
  } catch (e) {
    debugPrint('No se pudo procesar el botón de la notificación: $e');
  } finally {
    await db.close();
  }
}
