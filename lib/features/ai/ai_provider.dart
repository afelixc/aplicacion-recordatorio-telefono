/// Error al hablar con un proveedor de IA, con un mensaje para mostrar.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un proveedor de IA (Claude, OpenAI, Gemini…). Para sumar otro, crear una
/// clase que implemente esta interfaz y agregarla a `aiProviders`.
abstract class AiProvider {
  /// Identificador fijo (se guarda en la configuración).
  String get id;
  String get name;
  String get defaultModel;

  /// Cómo empieza una clave de este proveedor, para avisar si se pegó otra cosa.
  String get keyPrefix;

  /// Pasos del instructivo para conseguir la clave.
  List<String> get guideSteps;

  /// Página donde se crea la clave.
  String get keysUrl;

  /// Modelos disponibles con esta clave. Sirve también para probar la clave.
  Future<List<String>> listModels(String apiKey);

  /// Pide una respuesta en JSON que cumpla [schema] y la devuelve como texto.
  Future<String> completeJson({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
  });
}

/// Traduce los códigos de error HTTP más comunes a un mensaje claro.
AiException httpError(String provider, int status, String body) {
  final message = switch (status) {
    400 => 'El pedido no fue aceptado por $provider. Revisá el modelo elegido.',
    401 || 403 => 'La clave de $provider no es válida o no tiene permiso.',
    402 =>
      'Tu cuenta de $provider no tiene saldo. Cargá saldo y probá de nuevo.',
    404 =>
      'El modelo elegido no existe en $provider. Elegí otro en Configuración.',
    429 =>
      '$provider rechazó el pedido por límite de uso o falta de saldo. Esperá un rato o revisá tu saldo.',
    >= 500 => '$provider tiene problemas en este momento. Probá en un rato.',
    _ => 'Error de $provider ($status).',
  };
  return AiException(message);
}
