import 'ai_provider.dart';
import 'providers/claude_provider.dart';
import 'providers/gemini_provider.dart';
import 'providers/openai_provider.dart';

/// Proveedores disponibles. Para sumar uno, agregarlo a esta lista.
final List<AiProvider> aiProviders = [
  ClaudeProvider(),
  OpenAiProvider(),
  GeminiProvider(),
];

AiProvider providerById(String id) =>
    aiProviders.firstWhere((p) => p.id == id, orElse: () => aiProviders.first);
