import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/formatting.dart';
import '../../data/drift/database.dart';
import '../../data/drift/drift_reminder_repository.dart';
import '../../data/reminder.dart';
import '../../data/scheduling_reminder_repository.dart';
import 'reminder_actions.dart';
import 'reminder_scheduler.dart';
import 'snooze_options.dart';

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

  static const _channel = AndroidNotificationChannel(
    'recordatorios',
    'Recordatorios',
    description: 'Avisos de tus recordatorios a la hora indicada',
    importance: Importance.high,
  );

  Future<void> init() async {
    await _initTimeZone();
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
      launchReminderId = launch!.notificationResponse?.id;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Pide permiso para mostrar notificaciones (Android 13 en adelante).
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  Future<void> _onResponse(NotificationResponse response) async {
    final id = response.id;
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

  NotificationDetails _details(Reminder r) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
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

  @override
  Future<void> schedule(Reminder reminder) async {
    final id = reminder.id;
    if (id == null) return;
    await _plugin.cancel(id: id);
    if (reminder.done || !reminder.dueAt.isAfter(DateTime.now())) return;

    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: id,
      title: reminder.title,
      body: 'Recordatorio · ${Fmt.time(reminder.dueAt)} h',
      scheduledDate: tz.TZDateTime.from(reminder.dueAt, tz.local),
      notificationDetails: _details(reminder),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$id',
    );
  }

  @override
  Future<void> cancel(int reminderId) => _plugin.cancel(id: reminderId);

  @override
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    await _plugin.cancelAll();
    for (final r in reminders) {
      await schedule(r);
    }
  }
}

/// Botones de la notificación tocados con la app cerrada. Android lo ejecuta
/// aparte de la app, así que abre su propia conexión a la base.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  final id = response.id;
  if (id == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(Fmt.locale);
  await NotificationService._initTimeZone();
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
