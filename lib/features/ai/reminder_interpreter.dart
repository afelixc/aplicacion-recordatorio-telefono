import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import 'ai_provider.dart';

/// Resultado de interpretar un mensaje: hasta dos recordatorios listos para
/// guardar y, si a alguno le faltaba algo, la pregunta para completarlo.
class Interpretation {
  const Interpretation({
    this.reminders = const [],
    required this.message,
    this.question,
    this.tooMany = false,
    this.usage,
  });

  /// Los que se entendieron completos.
  final List<Reminder> reminders;

  /// Confirmación, o la pregunta si no se entendió ninguno.
  final String message;

  /// Pregunta por el que quedó incompleto (null si no falta nada).
  final String? question;

  /// Pidió más de [ReminderInterpreter.maxPerMessage]: el resto se ignoró.
  final bool tooMany;

  /// Tokens que usó la consulta (null si no se consultó a la IA).
  final AiResult? usage;

  Interpretation withUsage(AiResult usage) => Interpretation(
    reminders: reminders,
    message: message,
    question: question,
    tooMany: tooMany,
    usage: usage,
  );

  bool get ok => reminders.isNotEmpty;

  /// El primero (o null si no se entendió ninguno).
  Reminder? get reminder => reminders.isEmpty ? null : reminders.first;
}

/// Convierte lo que el usuario escribe o dice ("recordame el viernes a las 9
/// lavar el auto") en un recordatorio, usando el proveedor de IA elegido.
class ReminderInterpreter {
  ReminderInterpreter({
    required this.provider,
    required this.apiKey,
    required this.model,
    required this.language,
  });

  final AiProvider provider;
  final String apiKey;
  final String model;

  /// Idioma de las respuestas, por ejemplo "es-AR".
  final String language;

  /// Cuántos recordatorios se pueden pedir en un mismo mensaje.
  static const maxPerMessage = 2;

  static const _item = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'ok',
      'title',
      'date',
      'time',
      'repeat',
      'weekdays',
      'dates',
      'in_minutes',
      'message',
    ],
    'properties': {
      'ok': {'type': 'boolean'},
      'title': {'type': 'string'},
      'date': {'type': 'string', 'description': 'AAAA-MM-DD'},
      'time': {'type': 'string', 'description': 'HH:mm, 24 horas'},
      'repeat': {
        'type': 'string',
        'enum': ['none', 'daily', 'weekly', 'monthly', 'yearly', 'dates'],
      },
      'weekdays': {
        'type': 'array',
        'items': {'type': 'integer'},
      },
      'dates': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'in_minutes': {
        'type': 'integer',
        'description': 'Minutos desde ahora si el pedido es relativo; si no, 0',
      },
      'message': {'type': 'string'},
    },
  };

  static const schema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': ['reminders', 'message'],
    'properties': {
      'reminders': {'type': 'array', 'items': _item},
      'message': {'type': 'string'},
    },
  };

  static String systemPrompt(DateTime now, String language) {
    final today = DateFormat('EEEE yyyy-MM-dd HH:mm', 'es_AR').format(now);
    return '''
Sos el asistente de una app de recordatorios. Convertís el mensaje del usuario en recordatorios.
Ahora es $today (hora del teléfono del usuario).

Un mismo mensaje puede pedir uno o varios recordatorios distintos ("en 1 minuto lente y en 3 minutos pelota" son dos). Poné cada uno como un elemento de "reminders", en el orden en que los dijo. Si el mensaje no pide ninguno, devolvé "reminders" con un solo elemento con ok false.
"message" (afuera de la lista): una confirmación corta, o la pregunta si no se entendió nada. Escribilo en el idioma $language.

Completá cada elemento de "reminders" así:
- ok: true si se entiende qué recordar y cuándo. false solo si falta qué recordar, si no dice nada de cuándo, o si el mensaje no es un pedido de recordatorio. "En 15 minutos", "en media hora", "en 2 horas", "dentro de un rato" (= 30 minutos) son un cuándo válido: ok true, no preguntes.
- title: qué hay que recordar, breve, con mayúscula inicial y sin la fecha ni la hora. Ejemplo: "Recordame el viernes a las 9 lavar el auto" → "Lavar el auto". En el mismo idioma que usó el usuario.
- date: la primera fecha en que toca, AAAA-MM-DD. Calculá las fechas relativas desde ahora: "mañana", "pasado mañana", "el viernes" (el próximo; si hoy es ese día y la hora ya pasó, el de la semana siguiente), "en 2 horas", "el 15" (de este mes, o del próximo si ya pasó).
- time: hora en formato de 24 horas HH:mm. "9 de la mañana" = 09:00, "3 de la tarde" = 15:00, "8 de la noche" = 20:00, "mediodía" = 12:00. Si no dice la hora, usá 09:00.
- in_minutes: si el cuándo es relativo a ahora ("en 15 minutos" → 15, "en media hora" → 30, "en 2 horas" → 120, "en una hora y media" → 90), la cantidad de minutos. Igual completá date y time con la cuenta hecha. Si no es relativo, 0.
- repeat: "none" si es una sola vez; "daily" todos los días; "weekly" todas las semanas; "monthly" todos los meses; "yearly" todos los años; "dates" si nombra varias fechas sueltas.
- weekdays: solo con "weekly", los días de la semana del 1 (lunes) al 7 (domingo), por ejemplo "lunes y jueves" → [1, 4]. Si no, [].
- dates: solo con "dates", todas las fechas AAAA-MM-DD. Si no, [].
- message: si ok es false, una pregunta corta para pedir lo que falta de ESE recordatorio, nombrándolo (por ejemplo "¿A qué hora querés que te recuerde lo de la pelota?"). Si ok es true, una confirmación corta. Escribilo en el idioma $language.
Si ok es false, igual completá los demás campos con lo que se pueda ("" o [] si no hay nada). Si un recordatorio está completo y otro no, el completo va con ok true igual.''';
  }

  Future<Interpretation> interpret(String text, {DateTime? now}) async {
    now ??= DateTime.now();
    final result = await provider.completeJson(
      apiKey: apiKey,
      model: model,
      system: systemPrompt(now, language),
      user: text,
      schema: schema,
    );
    return parse(result.text, now: now).withUsage(result);
  }

  /// Convierte la respuesta JSON de la IA en recordatorios.
  static Interpretation parse(String raw, {DateTime? now}) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException(
        'La IA devolvió una respuesta que no se entiende. Probá de nuevo.',
      );
    }
    // Las respuestas viejas (un solo recordatorio, sin lista) también sirven.
    final list = j['reminders'];
    final items = list is List
        ? [
            for (final e in list)
              if (e is Map<String, dynamic>) e,
          ]
        : [j];
    final reminders = <Reminder>[];
    String? question;
    for (final item in items.take(maxPerMessage)) {
      final (reminder, ask) = _parseOne(item, now);
      if (reminder != null) {
        reminders.add(reminder);
      } else if (question == null && ask.isNotEmpty) {
        question = ask;
      }
    }
    final general = list is List ? (j['message'] as String?)?.trim() ?? '' : '';
    const fallback = '¿Qué querés que te recuerde y cuándo?';
    if (reminders.isEmpty) {
      return Interpretation(
        message: question ?? (general.isEmpty ? fallback : general),
      );
    }
    return Interpretation(
      reminders: reminders,
      message: general,
      question: question,
      tooMany: items.length > maxPerMessage,
    );
  }

  /// Un elemento de la lista: el recordatorio, o null y la pregunta.
  static (Reminder?, String) _parseOne(Map<String, dynamic> j, DateTime? now) {
    final message = (j['message'] as String?)?.trim() ?? '';
    final title = (j['title'] as String?)?.trim() ?? '';
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    final time = RegExp(r'^(\d{1,2}):(\d{2})')
        .firstMatch(j['time'] as String? ?? '');
    // "En 15 minutos": la cuenta se hace acá, con la hora exacta del teléfono.
    final inMinutes = j['in_minutes'];
    if (inMinutes is int &&
        inMinutes > 0 &&
        title.isNotEmpty &&
        (j['repeat'] == null || j['repeat'] == 'none')) {
      final at = (now ?? DateTime.now()).add(Duration(minutes: inMinutes));
      return (
        Reminder(
          title: title[0].toUpperCase() + title.substring(1),
          dueAt: DateTime(at.year, at.month, at.day, at.hour, at.minute),
        ),
        message,
      );
    }
    if (j['ok'] != true || title.isEmpty || date == null) {
      return (null, message);
    }
    final hour = time == null ? 9 : int.parse(time.group(1)!).clamp(0, 23);
    final minute = time == null ? 0 : int.parse(time.group(2)!).clamp(0, 59);
    final dueAt = DateTime(date.year, date.month, date.day, hour, minute);

    final weekdays = {
      for (final d in (j['weekdays'] as List? ?? const []))
        if (d is int && d >= 1 && d <= 7) d,
    };
    final dates = [
      for (final s in (j['dates'] as List? ?? const []))
        if (s is String && DateTime.tryParse(s) != null) DateTime.parse(s),
    ];
    final recurrence = switch (j['repeat']) {
      'daily' => const Recurrence.daily(),
      'weekly' => Recurrence.weekly(
        weekdays.isEmpty ? {dueAt.weekday} : weekdays,
      ),
      'monthly' => const Recurrence.monthly(),
      'yearly' => const Recurrence.yearly(),
      'dates' when dates.isNotEmpty => Recurrence.dates(dates),
      _ => const Recurrence.none(),
    };
    // En "días puntuales" la fecha del recordatorio es la primera de la lista.
    final first = recurrence.kind == RepeatKind.dates
        ? recurrence.dates.first
        : dueAt;
    return (
      Reminder(
        title: title[0].toUpperCase() + title.substring(1),
        dueAt: DateTime(first.year, first.month, first.day, hour, minute),
        recurrence: recurrence,
      ),
      message,
    );
  }
}
