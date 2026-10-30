/// Precio de un modelo en dólares por millón de tokens.
class ModelPrice {
  const ModelPrice(this.inputPerMillion, this.outputPerMillion);

  final double inputPerMillion;
  final double outputPerMillion;

  double cost(int inputTokens, int outputTokens) =>
      (inputTokens * inputPerMillion + outputTokens * outputPerMillion) /
      1000000;
}

/// Precios conocidos (dólares por millón de tokens de entrada / salida).
/// Se busca por el comienzo del nombre del modelo; el más largo gana.
/// Los de OpenAI y Gemini no están: cambian seguido y no los pude confirmar,
/// así que para esos modelos se muestran solo los tokens.
const _prices = <String, ModelPrice>{
  'claude-haiku-5-5': ModelPrice(0.10, 0.50),
  'claude-haiku-4-5': ModelPrice(1, 5),
  'claude-sonnet-5-5': ModelPrice(2, 10),
  'claude-sonnet-5': ModelPrice(2, 10),
  'claude-sonnet-4-6': ModelPrice(3, 15),
  'claude-opus-5-5': ModelPrice(4, 20),
  'claude-opus-5': ModelPrice(5, 25),
  'claude-opus-4': ModelPrice(5, 25),
  'claude-fable-5': ModelPrice(10, 50),
};

/// Precio del modelo, o null si no se conoce.
ModelPrice? priceFor(String model) {
  String? best;
  for (final prefix in _prices.keys) {
    if (model.startsWith(prefix) &&
        (best == null || prefix.length > best.length)) {
      best = prefix;
    }
  }
  return best == null ? null : _prices[best];
}
