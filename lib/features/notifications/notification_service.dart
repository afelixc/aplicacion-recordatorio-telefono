import 'dart:async';
import 'dart:typed_data';

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
import 'priority_config.dart';
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
    this.volume,
  });

  final bool enabled;
  final bool exactAlarms;
  final int pending;
  final String timeZone;
  final String? lastError;

  /// Volumen de las notificaciones (null si no se sabe).
  final SoundVolume? volume;
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

  /// Lo que hace cada prioridad (media y alta repiten el aviso).
  PriorityConfig priorities = const PriorityConfig();

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
    priorities = PriorityConfig.decode(p.getString(prioritiesKey));
  }

  static const prioritiesKey = 'prioridades';

  /// Guarda lo que hace cada prioridad. Después hay que volver a programar
  /// los avisos (`resync`).
  Future<void> setPriorities(PriorityConfig config) async {
    priorities = config;
    final p = await SharedPreferences.getInstance();
    await p.setString(prioritiesKey, config.encode());
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
      await _android?.deleteNotificationChannel(channelId: '${old}_fuerte');
      _created.remove('${old}_fuerte');
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
    volume: await SoundPicker.volume(),
  );

  /// Muestra un aviso de prueba ahora mismo. Devuelve un aviso si el volumen
  /// de las notificaciones está en cero.
  Future<String?> showTest() => showPriorityTest(
    ReminderPriority.normal,
    title: 'Aviso de prueba',
    body: 'Si ves esto, las notificaciones funcionan.',
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

  /// Permiso para que la prioridad alta ocupe toda la pantalla (Android 14).
  Future<void> requestFullScreen() async =>
      _android?.requestFullScreenIntentPermission();

  Future<void> requestExactAlarms() async =>
      _android?.requestExactAlarmsPermission();

  /// Abre los ajustes de notificaciones de la app.
  Future<void> openNotificationSettings() => const AndroidIntent(
    action: 'android.settings.APP_NOTIFICATION_SETTINGS',
    arguments: {'android.provider.extra.APP_PACKAGE': _package},
  ).launch();

  /// Pide permiso para mostrar notificaciones (Android 13 en adelante).
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  Future<void> _onResponse(NotificationResponse response) async {
    // El aviso de prueba: tocarlo corta el sonido.
    if (response.id == 0) unawaited(SoundPicker.stop());
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

  NotificationDetails _details() => _build(_channel);

  List<AndroidNotificationAction> get _actions => [
    const AndroidNotificationAction(ReminderActions.doneActionId, 'Hecho'),
    for (final o in snoozeOptions.where((o) => o.showInNotification))
      AndroidNotificationAction(o.id, o.label),
  ];

  NotificationDetails _build(
    AndroidNotificationChannel ch, {
    bool alarm = false,
    bool insistent = false,
    bool fullScreen = false,
    int? timeoutMs,
    bool max = false,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      ch.id,
      ch.name,
      channelDescription: ch.description,
      importance: ch.importance,
      sound: ch.sound,
      playSound: ch.playSound,
      enableVibration: ch.enableVibration,
      vibrationPattern: ch.vibrationPattern,
      priority: max ? Priority.max : Priority.high,
      category: alarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      audioAttributesUsage: ch.audioAttributesUsage,
      additionalFlags: insistent ? Int32List.fromList(const [4]) : null,
      fullScreenIntent: fullScreen,
      timeoutAfter: timeoutMs,
      groupKey: 'recordame',
      color: const Color(0xFF2B3A67),
      actions: _actions,
    ),
  );

  // --- Canales de las prioridades ---
  // Android fija el sonido y la vibración de cada canal: hay uno por sonido.
  // Los que terminan en "_fuerte" suenan con el volumen de la alarma, aunque
  // el teléfono esté en silencio o en "No molestar".

  final _created = <String>{};

  static String _raw(String id) => 'android.resource://$_package/raw/$id';

  AndroidNotificationChannel _loud(AndroidNotificationChannel c) =>
      AndroidNotificationChannel(
        '${c.id}_fuerte',
        '${c.name} (aunque esté en silencio)',
        description: c.description,
        importance: Importance.max,
        sound: c.sound,
        playSound: c.playSound,
        enableVibration: c.enableVibration,
        vibrationPattern: c.vibrationPattern,
        bypassDnd: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

  /// Clave corta y fija para el nombre del canal de un sonido del teléfono
  /// (Android no deja cambiar el sonido de un canal: uno por sonido).
  static String soundKey(String uri) {
    var h = 0x811c9dc5;
    for (final c in uri.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(36);
  }

  AndroidNotificationChannel _mediaChannel() {
    final id = priorities.mediaSound;
    if (id == PriorityConfig.appSound) return _channel;
    if (priorities.mediaFromPhone) {
      final uri = priorities.mediaPhoneUri!;
      return AndroidNotificationChannel(
        'prio_media_tel_${soundKey(uri)}',
        'Prioridad media · ${priorities.mediaSoundName}',
        description: 'Avisos que se repiten hasta tocar Hecho',
        importance: Importance.high,
        sound: UriAndroidNotificationSound(uri),
      );
    }
    return AndroidNotificationChannel(
      'prio_media_${priorities.mediaSoundId}',
      'Prioridad media · ${priorities.mediaSoundName}',
      description: 'Avisos que se repiten hasta tocar Hecho',
      importance: Importance.high,
      sound: UriAndroidNotificationSound(_raw(priorities.mediaSoundId)),
    );
  }

  AndroidNotificationChannel _altaChannel() {
    final phone = priorities.altaFromPhone;
    final key = phone
        ? 'tel_${soundKey(priorities.altaPhoneUri!)}'
        : priorities.altaSoundInfo.id;
    final vib = priorities.altaVibrate;
    return AndroidNotificationChannel(
      'prio_alta_${key}_${vib ? 'v' : 'n'}',
      'Prioridad alta · ${priorities.altaSoundName}${vib ? ' · vibra' : ''}',
      description: 'Avisos que suenan seguido hasta tocar Hecho',
      importance: Importance.max,
      sound: UriAndroidNotificationSound(
        phone ? priorities.altaPhoneUri! : _raw(key),
      ),
      enableVibration: vib,
      vibrationPattern: vib
          ? Int64List.fromList(const [0, 900, 300, 900, 300, 900, 300, 900])
          : null,
    );
  }

  /// Sin sonido: queda a la vista después de que sonó la prioridad alta.
  static const _quiet = AndroidNotificationChannel(
    'recordame_quedan',
    'Avisos que quedan a la vista',
    description: 'El aviso que queda después de sonar la prioridad alta',
    importance: Importance.defaultImportance,
    playSound: false,
    enableVibration: false,
  );

  Future<AndroidNotificationChannel> _ensure(
    AndroidNotificationChannel c,
  ) async {
    if (_created.add(c.id)) await _android?.createNotificationChannel(c);
    return c;
  }

  /// Cómo suena el aviso de un recordatorio según su prioridad.
  Future<NotificationDetails> _detailsFor(Reminder r, {int? timeoutMs}) async {
    switch (r.priority) {
      case ReminderPriority.normal:
        final ch = await _ensure(r.loud ? _loud(_channel) : _channel);
        return _build(ch, alarm: r.loud);
      case ReminderPriority.media:
        final base = _mediaChannel();
        final ch = await _ensure(r.loud ? _loud(base) : base);
        return _build(ch, alarm: r.loud, timeoutMs: timeoutMs);
      case ReminderPriority.alta:
        final base = _altaChannel();
        final ch = await _ensure(r.loud ? _loud(base) : base);
        return _build(
          ch,
          alarm: true,
          max: true,
          insistent: true,
          fullScreen: priorities.altaFullScreen,
          timeoutMs: _ringMillis,
        );
    }
  }

  /// Lo que suena cada aviso de prioridad alta ("cuántas veces seguido").
  /// Nunca más de 55 segundos, para que no se pise con la repetición.
  int get _ringMillis =>
      (priorities.altaMillis * priorities.altaTimes + 300).clamp(1000, 55000);

  /// Sonido de cada prioridad (null = el de notificación del teléfono).
  String? soundUriFor(ReminderPriority p) => switch (p) {
    ReminderPriority.normal => _soundUri,
    ReminderPriority.media =>
      priorities.mediaSound == PriorityConfig.appSound
          ? _soundUri
          : priorities.mediaFromPhone
          ? priorities.mediaPhoneUri
          : _raw(priorities.mediaSoundId),
    ReminderPriority.alta =>
      priorities.altaFromPhone
          ? priorities.altaPhoneUri
          : _raw(priorities.altaSoundInfo.id),
  };

  /// Cada recordatorio usa los números de aviso `id * 100` a `id * 100 + 99`:
  /// uno por cada día de la semana o fecha suelta, y el último para "Posponer".
  /// En la prioridad alta, `+ 50` es el aviso que queda a la vista después de
  /// sonar. Las repeticiones de media y alta usan `_repeatBase + id * 100 + n`.
  static const _slots = 100;
  static const _snoozeSlot = 99;
  static const _staySlot = 50;
  static const _repeatBase = 1000000000;

  static int _ownerOf(int notificationId) => notificationId >= _repeatBase
      ? (notificationId - _repeatBase) ~/ _slots
      : notificationId ~/ _slots;

  /// Recordatorio al que pertenece un aviso.
  static int? reminderIdOf(NotificationResponse response) =>
      int.tryParse(response.payload ?? '') ??
      (response.id == null ? null : _ownerOf(response.id!));

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
      // Media y alta usan el modo "despertador" de Android, que no se demora
      // con la pantalla apagada.
      final mode = !exact
          ? AndroidScheduleMode.inexactAllowWhileIdle
          : reminder.priority == ReminderPriority.normal
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.alarmClock;
      final details = await _detailsFor(reminder);
      final alta = reminder.priority == ReminderPriority.alta;
      final stay = alta ? _build(await _ensure(_quiet)) : null;

      Future<void> post(
        int notificationId,
        DateTime when,
        NotificationDetails d, [
        DateTimeComponents? repeat,
      ]) => _plugin.zonedSchedule(
        id: notificationId,
        title: reminder.title,
        body: 'Recordatorio · ${Fmt.time(when)} h',
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: d,
        androidScheduleMode: mode,
        matchDateTimeComponents: repeat,
        payload: '$id',
      );

      Future<void> at(
        int slot,
        DateTime when, [
        DateTimeComponents? repeat,
      ]) async {
        await post(id * _slots + slot, when, details, repeat);
        // La alta suena un rato y se va; después queda este, sin sonido.
        if (stay != null) {
          final after = when.add(Duration(milliseconds: _ringMillis + 1000));
          final staySlot = slot == _snoozeSlot ? 98 : slot + _staySlot;
          await post(id * _slots + staySlot, after, stay, repeat);
        }
      }

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

      // Media y alta: vuelve a avisar cada tanto hasta que se toque "Hecho".
      final times = repeatTimes(reminder, priorities, now);
      for (var n = 0; n < times.length; n++) {
        final last = n == times.length - 1;
        final d = reminder.priority == ReminderPriority.media
            ? await _detailsFor(
                reminder,
                // Cada repetición se va cuando llega la siguiente.
                timeoutMs: last ? null : priorities.mediaEvery * 60000 - 3000,
              )
            : details;
        await post(_repeatBase + id * _slots + n + 1, times[n], d);
      }
      lastError = null;
    } catch (e) {
      // El recordatorio queda guardado igual; el error se ve en Configuración.
      lastError = '$e';
      debugPrint('No se pudo programar el aviso $id: $e');
    }
  }

  /// Horas en las que se repite el aviso de un recordatorio de prioridad
  /// media o alta: las de la vez que toca ahora (o la próxima), que todavía
  /// no pasaron. La vez ya hecha o pospuesta no se repite.
  static List<DateTime> repeatTimes(
    Reminder r,
    PriorityConfig config,
    DateTime now,
  ) {
    if (r.done || r.priority == ReminderPriority.normal) return const [];
    List<DateTime> repeatsOf(DateTime first) =>
        r.priority == ReminderPriority.media
        ? config.mediaRepeats(first)
        : config.altaRepeats(first);
    DateTime? first;
    if (!r.repeats) {
      first = r.dueAt;
    } else {
      // La vez más vieja que todavía se estaría repitiendo.
      const lookBack = Duration(hours: 24);
      first = r.recurrence.nextAfter(r.dueAt, now.subtract(lookBack));
      while (first != null && !first.isAfter(now)) {
        final repeats = repeatsOf(first);
        final doneThis = r.lastDoneAt != null && !r.lastDoneAt!.isBefore(first);
        final snoozedThis =
            r.snoozedUntil != null && r.snoozedUntil!.isAfter(first);
        final active =
            repeats.isNotEmpty && repeats.last.isAfter(now) && !doneThis;
        if (active && !snoozedThis) break;
        first = r.recurrence.nextAfter(
          r.dueAt,
          first.add(const Duration(minutes: 1)),
        );
      }
    }
    final out = first == null
        ? <DateTime>[]
        : repeatsOf(first).where((t) => t.isAfter(now)).toList();
    // Uno que se repite y se pospuso ("1 hora", "Mañana"): a esa hora vuelve
    // a empezar a repetir, igual que uno que no se repite.
    final snoozed = r.snoozedUntil;
    final doneAfter =
        snoozed != null &&
        r.lastDoneAt != null &&
        !r.lastDoneAt!.isBefore(snoozed);
    if (r.repeats && snoozed != null && !doneAfter) {
      final again = repeatsOf(snoozed).where((t) => t.isAfter(now)).toList();
      if (again.isNotEmpty) {
        // Mientras repite lo pospuesto, no se suman las de la vez normal.
        out.removeWhere((t) => !t.isBefore(snoozed) && !t.isAfter(again.last));
        out.addAll(again);
        out.sort();
      }
    }
    final unique = out.toSet().toList();
    return unique.length > PriorityConfig.maxRepeats
        ? unique.sublist(0, PriorityConfig.maxRepeats)
        : unique;
  }

  @override
  Future<void> cancel(int reminderId) async {
    for (final p in await _plugin.pendingNotificationRequests()) {
      // `p.id == reminderId`: avisos de la versión 1.0.5 o anterior.
      if (_ownerOf(p.id) == reminderId || p.id == reminderId) {
        await _plugin.cancel(id: p.id);
      }
    }
    // Los que están a la vista (los que se repiten quedan varios).
    try {
      for (final a in await _plugin.getActiveNotifications()) {
        final nid = a.id;
        if (nid != null && nid != 0 && _ownerOf(nid) == reminderId) {
          await _plugin.cancel(id: nid);
        }
      }
    } catch (_) {}
  }

  /// Para la prueba: sin sonido (lo hace sonar la app), con o sin vibrar.
  static final _testVibrate = AndroidNotificationChannel(
    'prueba_vibra',
    'Avisos de prueba',
    description: 'El aviso de "Probar"; el sonido lo hace la app',
    importance: Importance.high,
    playSound: false,
    vibrationPattern: Int64List.fromList(const [0, 400, 200, 400]),
  );
  static const _testQuiet = AndroidNotificationChannel(
    'prueba_sin_vibrar',
    'Avisos de prueba (sin vibrar)',
    description: 'El aviso de "Probar"; el sonido lo hace la app',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );

  /// Hace sonar un aviso de prueba con la prioridad elegida.
  ///
  /// Con la app abierta, algunos teléfonos muestran el aviso y vibran pero no
  /// lo hacen sonar: por eso el aviso de prueba va sin sonido y el sonido lo
  /// hace la app (el mismo y con el mismo volumen que el recordatorio).
  /// Devuelve un mensaje si no se va a escuchar.
  Future<String?> showPriorityTest(
    ReminderPriority priority, {
    bool loud = false,
    String? title,
    String body = 'Así te va a sonar.',
  }) async {
    final alta = priority == ReminderPriority.alta;
    final vibrate = !alta || priorities.altaVibrate;
    final ch = await _ensure(vibrate ? _testVibrate : _testQuiet);
    await _plugin.show(
      id: 0,
      title: title ?? 'Prueba · prioridad ${priority.label.toLowerCase()}',
      body: body,
      notificationDetails: _build(
        ch,
        max: alta,
        timeoutMs: alta ? _ringMillis : null,
      ),
    );
    final error = await SoundPicker.test(
      soundUriFor(priority),
      alarm: loud,
      millis: alta ? _ringMillis : 4000,
      loop: alta,
    );
    final v = await SoundPicker.volume();
    if (v != null) {
      if (loud && !v.alarmAudible) {
        return 'El volumen de la alarma está en cero.';
      }
      if (!loud && !v.notificationsAudible) return '${v.notificationsText}.';
    }
    if (error != null) return 'No se pudo hacer sonar ese sonido ($error).';
    return null;
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
