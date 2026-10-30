import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_provider.dart';

/// Claude, de Anthropic (Messages API).
class ClaudeProvider implements AiProvider {
  ClaudeProvider({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://api.anthropic.com/v1';

  @override
  String get id => 'claude';
  @override
  String get name => 'Claude (Anthropic)';
  @override
  String get defaultModel => 'claude-haiku-5-5';
  @override
  List<(String, String)> get suggestedModels => const [
    (
      'claude-haiku-5-5',
      'Haiku 5.5: rápido y el más económico. Para recordatorios alcanza y sobra (recomendado).',
    ),
    (
      'claude-sonnet-5-5',
      'Sonnet 5.5: intermedio. Unas 20 veces más caro que Haiku.',
    ),
    (
      'claude-opus-5-5',
      'Opus 5.5: el más capaz, pensado para tareas difíciles. Unas 40 veces más caro que Haiku; para recordatorios no hace falta.',
    ),
  ];
  @override
  String get keyPrefix => 'sk-ant-';
  @override
  String get keysUrl => 'https://console.anthropic.com/settings/keys';
  @override
  String get billingUrl => 'https://console.anthropic.com/settings/billing';
  @override
  List<String> get guideSteps => const [
    'Entrá a console.anthropic.com y creá una cuenta (podés usar tu correo de Google).',
    'Andá a "Billing" (Facturación), agregá una tarjeta y cargá saldo. Con el mínimo alcanza para muchísimos recordatorios.',
    'Andá a "API Keys" y tocá "Create Key". Ponele un nombre, por ejemplo "Recordame".',
    'Copiá la clave (empieza con sk-ant-). Se muestra una sola vez.',
    'Pegala acá abajo, tocá "Guardar" y después "Probar clave".',
  ];

  Map<String, String> _headers(String key) => {
    'x-api-key': key,
    'anthropic-version': '2026-10-21',
    'content-type': 'application/json',
  };

  @override
  Future<List<String>> listModels(String apiKey) async {
    final r = await _http.get(
      Uri.parse('$_base/models?limit=100'),
      headers: _headers(apiKey),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final data = (jsonDecode(r.body)['data'] as List).cast<Map>();
    return [for (final m in data) m['id'] as String];
  }

  @override
  Future<AiResult> completeJson({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
  }) async {
    // Si el modelo rechaza el pedido por sus filtros de seguridad, la API lo
    // reintenta sola con otro modelo (solo en los modelos que lo admiten).
    final fallbacks =
        model.startsWith('claude-opus-5') ||
        model.startsWith('claude-fable-5') ||
        model.startsWith('claude-sonnet-5-5');
    final r = await _http.post(
      Uri.parse('$_base/messages'),
      headers: {
        ..._headers(apiKey),
        if (fallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 4096,
        'system': system,
        'messages': [
          {'role': 'user', 'content': user},
        ],
        'output_config': {
          // Interpretar un recordatorio es una tarea simple: poco razonamiento.
          'effort': 'low',
          'format': {'type': 'json_schema', 'schema': schema},
        },
        if (fallbacks) 'fallbacks': 'default',
      }),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (json['stop_reason'] == 'refusal') {
      throw const AiException('Claude no quiso responder ese pedido.');
    }
    final text = (json['content'] as List)
        .cast<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    if (text.isEmpty) throw const AiException('Claude no devolvió respuesta.');
    final usage = json['usage'] as Map? ?? const {};
    return AiResult(
      text,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
