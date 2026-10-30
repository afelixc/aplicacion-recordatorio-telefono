import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/features/ai/ai_provider.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/features/ai/providers/claude_provider.dart';
import 'package:recordame/features/ai/providers/gemini_provider.dart';
import 'package:recordame/features/ai/providers/openai_provider.dart';
import 'package:recordame/features/ai/reminder_interpreter.dart';

const _answer = {
  'ok': true,
  'title': 'lavar el auto',
  'date': '2026-11-06',
  'time': '09:00',
  'repeat': 'none',
  'weekdays': [],
  'dates': [],
  'message': 'Listo',
};

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('interpretar la respuesta', () {
    test('un recordatorio simple', () {
      final r = ReminderInterpreter.parse(jsonEncode(_answer));
      expect(r.ok, isTrue);
      expect(r.reminder!.title, 'Lavar el auto');
      expect(r.reminder!.dueAt, DateTime(2026, 11, 6, 9));
      expect(r.reminder!.recurrence.kind, RepeatKind.none);
    });

    test('semanal con días', () {
      final r = ReminderInterpreter.parse(
        jsonEncode({
          ..._answer,
          'title': 'Gimnasio',
          'time': '19:30',
          'repeat': 'weekly',
          'weekdays': [1, 4, 9],
        }),
      );
      expect(r.reminder!.recurrence.weekdays, {1, 4});
      expect(r.reminder!.dueAt.hour, 19);
      expect(r.reminder!.dueAt.minute, 30);
    });

    test('días puntuales: la fecha es la primera', () {
      final r = ReminderInterpreter.parse(
        jsonEncode({
          ..._answer,
          'repeat': 'dates',
          'dates': ['2026-11-20', '2026-11-10'],
        }),
      );
      expect(r.reminder!.recurrence.kind, RepeatKind.dates);
      expect(r.reminder!.dueAt, DateTime(2026, 11, 10, 9));
    });

    test('si falta algo, devuelve la pregunta', () {
      final r = ReminderInterpreter.parse(
        jsonEncode({..._answer, 'ok': false, 'message': '¿A qué hora?'}),
      );
      expect(r.ok, isFalse);
      expect(r.message, '¿A qué hora?');
    });

    test('respuesta rota', () {
      expect(
        () => ReminderInterpreter.parse('no es json'),
        throwsA(isA<AiException>()),
      );
    });

    test('el pedido incluye la fecha de hoy', () {
      final prompt = ReminderInterpreter.systemPrompt(
        DateTime(2026, 10, 30, 10),
        'es-AR',
      );
      expect(prompt, contains('viernes 2026-10-30 10:00'));
    });
  });

  group('proveedores', () {
    Future<(http.Request, String)> call(
      AiProvider Function(http.Client) make,
      String responseBody,
    ) async {
      late http.Request sent;
      final provider = make(
        MockClient((req) async {
          sent = req;
          return http.Response(responseBody, 200);
        }),
      );
      final text = await provider.completeJson(
        apiKey: 'clave',
        model: provider.defaultModel,
        system: 'sistema',
        user: 'usuario',
        schema: ReminderInterpreter.schema,
      );
      return (sent, text);
    }

    test('Claude', () async {
      final (req, text) = await call(
        (c) => ClaudeProvider(client: c),
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': jsonEncode(_answer)},
          ],
        }),
      );
      expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'clave');
      expect(req.headers['anthropic-version'], '2026-10-21');
      final body = jsonDecode(req.body);
      expect(body['model'], 'claude-opus-5-5');
      expect(body['output_config']['format']['type'], 'json_schema');
      expect(body['fallbacks'], 'default');
      expect(jsonDecode(text)['title'], 'lavar el auto');
    });

    test('Claude rechaza el pedido', () async {
      expect(
        call(
          (c) => ClaudeProvider(client: c),
          jsonEncode({'stop_reason': 'refusal', 'content': []}),
        ),
        throwsA(isA<AiException>()),
      );
    });

    test('OpenAI', () async {
      final (req, text) = await call(
        (c) => OpenAiProvider(client: c),
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(_answer)},
            },
          ],
        }),
      );
      expect(req.url.path, '/v1/chat/completions');
      expect(req.headers['authorization'], 'Bearer clave');
      final body = jsonDecode(req.body);
      expect(body['response_format']['json_schema']['strict'], isTrue);
      expect(jsonDecode(text)['ok'], isTrue);
    });

    test('Gemini (sin additionalProperties en el esquema)', () async {
      final (req, text) = await call(
        (c) => GeminiProvider(client: c),
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(_answer)},
                ],
              },
            },
          ],
        }),
      );
      expect(req.url.path, '/v1beta/models/gemini-3.5-flash:generateContent');
      expect(req.headers['x-goog-api-key'], 'clave');
      expect(req.body, isNot(contains('additionalProperties')));
      expect(jsonDecode(text)['date'], '2026-11-06');
    });

    test('errores HTTP con mensajes claros', () async {
      final provider = ClaudeProvider(
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      expect(
        provider.listModels('mala'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('no es válida'),
          ),
        ),
      );
    });
  });
}
