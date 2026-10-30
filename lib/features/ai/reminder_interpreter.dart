import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import 'ai_provider.dart';

/// Resultado de interpretar un mensaje: un recordatorio para confirmar, o una
/// pregunta si faltaba algo.
class Interpretation {
  const Interpretation({this.reminder, required this.message, this.usage});

  final Reminder? reminder;
  final String message;

  /// Tokens que usó la consulta (null si no se consultó a la IA).
  final AiResult? usage;

  Interpretation withUsage(AiResult usage) =>
      Interpretation(reminder: reminder, message: message, usage: usage);

  bool get ok => reminder != null;
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

  static const schema = <String, dynamic>{
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
      'message': {'type': 'string'},
    },
  };

  static String systemPrompt(DateTime now, String language) {
    final today = DateFormat('EEEE yyyy-MM-dd HH:mm', 'es_AR').format(now);
    return '''
Sos el asistente de una app de recordatorios. Convertís el mensaje del usuario en un recordatorio.
Ahora es $today (hora del teléfono del usuario).

Completá el JSON así:
- ok: true si se entiende qué recordar y cuándo. false si falta qué recordar, si la fecha es ambigua de verdad, o si el mensaje no es un pedido de recordatorio.
- title: qué hay que recordar, breve, con mayúscula inicial y sin la fecha ni la hora. Ejemplo: "Recordame el viernes a las 9 lavar el auto" → "Lavar el auto". En el mismo idioma que usó el usuario.
- date: la primera fecha en que toca, AAAA-MM-DD. Calculá las fechas relativas desde ahora: "mañana", "pasado mañana", "el viernes" (el próximo; si hoy es ese día y la hora ya pasó, el de la semana siguiente), "en 2 horas", "el 15" (de este mes, o del próximo si ya pasó).
- time: hora en formato de 24 horas HH:mm. "9 de la mañana" = 09:00, "3 de la tarde" = 15:00, "8 de la noche" = 20:00, "mediodía" = 12:00. Si no dice la hora, usá 09:00.
- repeat: "none" si es una sola vez; "daily" todos los días; "weekly" todas las semanas; "monthly" todos los meses; "yearly" todos los años; "dates" si nombra varias fechas sueltas.
- weekdays: solo con "weekly", los días de la semana del 1 (lunes) al 7 (domingo), por ejemplo "lunes y jueves" → [1, 4]. Si no, [].
- dates: solo con "dates", todas las fechas AAAA-MM-DD. Si no, [].
- message: si ok es false, una pregunta corta para pedir lo que falta. Si ok es true, una confirmación corta. Escribilo en el idioma $language.
Si ok es false, igual completá los demás campos con lo que se pueda ("" o [] si no hay nada).''';
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
    return parse(result.text).withUsage(result);
  }

  /// Convierte la respuesta JSON de la IA en un recordatorio.
  static Interpretation parse(String raw) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException(
        'La IA devolvió una respuesta que no se entiende. Probá de nuevo.',
      );
    }
    final message = (j['message'] as String?)?.trim() ?? '';
    final title = (j['title'] as String?)?.trim() ?? '';
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    final time = RegExp(r'^(\d{1,2}):(\d{2})')
        .firstMatch(j['time'] as String? ?? '');
    if (j['ok'] != true || title.isEmpty || date == null) {
      return Interpretation(
        message: message.isEmpty
            ? '¿Qué querés que te recuerde y cuándo?'
            : message,
      );
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
    return Interpretation(
      reminder: Reminder(
        title: title[0].toUpperCase() + title.substring(1),
        dueAt: DateTime(first.year, first.month, first.day, hour, minute),
        recurrence: recurrence,
      ),
      message: message,
    );
  }
}
