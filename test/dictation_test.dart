import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:recordame/features/chat/dictation.dart';

/// Reconocimiento de voz de mentira: la prueba manda los resultados.
class FakeSpeech implements SpeechToText {
  void Function(SpeechRecognitionResult)? onResult;
  void Function(String)? onStatus;
  bool listening = false;
  int listens = 0;

  void say(String words, {bool last = true}) => onResult!(
    SpeechRecognitionResult.init([
      SpeechRecognitionWords(words, null, 0.9),
    ], last ? ResultType.finalResult : ResultType.partial),
  );

  @override
  Future<bool> initialize({
    dynamic onError,
    dynamic onStatus,
    dynamic debugLogging = false,
    dynamic finalTimeout,
    dynamic options,
  }) async {
    this.onStatus = onStatus as void Function(String)?;
    return true;
  }

  @override
  bool get isListening => listening;

  @override
  Future<dynamic> listen({
    dynamic onResult,
    dynamic listenFor,
    dynamic pauseFor,
    dynamic localeId,
    dynamic onSoundLevelChange,
    dynamic cancelOnError = false,
    dynamic partialResults = true,
    dynamic onDevice = false,
    dynamic listenMode,
    dynamic sampleRate = 0,
    dynamic listenOptions,
  }) async {
    this.onResult = onResult as void Function(SpeechRecognitionResult);
    listens++;
    listening = true;
  }

  @override
  Future<void> stop() async => listening = false;

  @override
  Future<void> cancel() async => listening = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'dictado lento: no repite tramos y no pierde las últimas palabras',
    () async {
      final speech = FakeSpeech();
      final d = Dictation(speech: speech);
      await d.start(language: 'es-AR');

      speech.say('esta noche 11 de la noche');
      // Android repite el mismo tramo al reiniciar, a veces más corto...
      speech.say('esta noche 11');
      speech.say('Esta noche, 11 de la noche');
      // ...o más completo: reemplaza al anterior.
      speech.say('esta noche 11 de la noche recordame');
      speech.say('descargar serie', last: false);

      final text = d.finish(wait: const Duration(milliseconds: 200));
      // Las últimas palabras llegan justo después de tocar Enviar.
      speech.say('descargar la serie');
      expect(
        await text,
        'esta noche 11 de la noche recordame descargar la serie',
      );
    },
  );

  test('si no llega nada más, usa lo que estaba diciendo', () async {
    final speech = FakeSpeech();
    final d = Dictation(speech: speech);
    await d.start(language: 'es-AR');
    speech.say('recordame mañana');
    speech.say('comprar pan', last: false);
    expect(
      await d.finish(wait: const Duration(milliseconds: 50)),
      'recordame mañana comprar pan',
    );
  });

  test('una pausa larga reinicia una sola vez y no pierde nada', () async {
    final speech = FakeSpeech();
    final d = Dictation(speech: speech);
    await d.start(language: 'es-AR');
    speech.say('el martes a las 10', last: false);
    // Me quedé pensando: Android corta y avisa dos veces.
    speech.listening = false;
    speech.onStatus!(SpeechToText.doneStatus);
    speech.onStatus!(SpeechToText.notListeningStatus);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(speech.listens, 2);
    speech.say('llamar a Juan');
    expect(
      await d.finish(wait: const Duration(milliseconds: 50)),
      'el martes a las 10 llamar a Juan',
    );
  });
}
