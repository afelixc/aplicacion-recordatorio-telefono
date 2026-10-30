import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_provider.dart';

/// Gemini, de Google (Gemini API).
class GeminiProvider implements AiProvider {
  GeminiProvider({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  @override
  String get id => 'gemini';
  @override
  String get name => 'Gemini (Google)';
  @override
  String get defaultModel => 'gemini-3.5-flash';
  @override
  String get keyPrefix => 'AI';
  @override
  String get keysUrl => 'https://aistudio.google.com/app/apikey';
  @override
  List<String> get guideSteps => const [
    'Entrá a aistudio.google.com con tu cuenta de Google.',
    'Tocá "Get API key" y después "Create API key".',
    'Copiá la clave (empieza con AI).',
    'Gemini tiene un uso gratuito con límites. Si querés más, activá la facturación en Google Cloud.',
    'Pegala acá abajo, tocá "Guardar" y después "Probar clave".',
  ];

  Map<String, String> _headers(String key) => {
    'x-goog-api-key': key,
    'content-type': 'application/json',
  };

  @override
  Future<List<String>> listModels(String apiKey) async {
    final r = await _http.get(
      Uri.parse('$_base/models?pageSize=200'),
      headers: _headers(apiKey),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final models = (jsonDecode(r.body)['models'] as List).cast<Map>();
    return [
      for (final m in models)
        if ((m['supportedGenerationMethods'] as List?)?.contains(
              'generateContent',
            ) ??
            false)
          (m['name'] as String).replaceFirst('models/', ''),
    ];
  }

  /// Gemini no acepta "additionalProperties" en el esquema.
  static Object? _geminiSchema(Object? node) => switch (node) {
    Map() => {
      for (final e in node.entries)
        if (e.key != 'additionalProperties')
          e.key as String: _geminiSchema(e.value),
    },
    List() => node.map(_geminiSchema).toList(),
    _ => node,
  };

  @override
  Future<String> completeJson({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
  }) async {
    final r = await _http.post(
      Uri.parse('$_base/models/$model:generateContent'),
      headers: _headers(apiKey),
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': user},
            ],
          },
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': _geminiSchema(schema),
        },
      }),
    );
    if (r.statusCode != 200) throw httpError(name, r.statusCode, r.body);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    final parts = candidates?.isNotEmpty ?? false
        ? (candidates!.first['content']?['parts'] as List?)
        : null;
    final text = parts?.map((p) => p['text'] ?? '').join() ?? '';
    if (text.isEmpty) throw const AiException('Gemini no devolvió respuesta.');
    return text;
  }
}
