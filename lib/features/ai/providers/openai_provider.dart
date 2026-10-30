import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_provider.dart';

/// OpenAI (ChatGPT), con Chat Completions y salida JSON estricta.
class OpenAiProvider implements AiProvider {
  OpenAiProvider({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://api.openai.com/v1';

  @override
  String get id => 'openai';
  @override
  String get name => 'OpenAI (ChatGPT)';
  @override
  String get defaultModel => 'gpt-5-mini';
  @override
  String get keyPrefix => 'sk-';
  @override
  String get keysUrl => 'https://platform.openai.com/api-keys';
  @override
  String get billingUrl =>
      'https://platform.openai.com/settings/organization/billing/overview';
  @override
  List<String> get guideSteps => const [
    'Entrá a platform.openai.com y creá una cuenta. Ojo: es distinta de la suscripción a ChatGPT.',
    'Andá a "Settings" → "Billing", agregá una tarjeta y cargá saldo (el mínimo alcanza).',
    'Andá a "API keys" y tocá "Create new secret key". Ponele de nombre "Recordame".',
    'Copiá la clave (empieza con sk-). Se muestra una sola vez.',
    'Pegala acá abajo, tocá "Guardar" y después "Probar clave".',
  ];

  Map<String, String> _headers(String key) => {
    'authorization': 'Bearer $key',
    'content-type': 'application/json',
  };

  @override
  Future<List<String>> listModels(String apiKey) async {
    final r = await _http.get(
      Uri.parse('$_base/models'),
      headers: _headers(apiKey),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final data = (jsonDecode(r.body)['data'] as List).cast<Map>();
    return [
      for (final m in data)
        if ((m['id'] as String).startsWith('gpt-')) m['id'] as String,
    ]..sort();
  }

  @override
  Future<AiResult> completeJson({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
  }) async {
    final r = await _http.post(
      Uri.parse('$_base/chat/completions'),
      headers: _headers(apiKey),
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'recordatorio',
            'strict': true,
            'schema': schema,
          },
        },
      }),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final message = (json['choices'] as List).first['message'] as Map;
    final text = message['content'] as String?;
    if (text == null || text.isEmpty) {
      throw const AiException('OpenAI no devolvió respuesta.');
    }
    final usage = json['usage'] as Map? ?? const {};
    return AiResult(
      text,
      inputTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
