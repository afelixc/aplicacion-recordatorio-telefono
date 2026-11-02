import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictado por voz sin límite de tiempo.
///
/// El reconocimiento de Android se corta solo cuando uno hace una pausa; acá
/// se vuelve a poner a escuchar enseguida y se va juntando todo lo dicho, hasta
/// que el usuario toque Enviar o Cancelar.
class Dictation extends ChangeNotifier {
  Dictation({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _ready = false;
  bool _active = false;
  String _language = 'es-AR';

  /// Lo que ya quedó confirmado de los tramos anteriores.
  String _committed = '';

  /// Lo que se está diciendo en este momento (todavía puede cambiar).
  String _partial = '';

  /// El último tramo que se guardó (para no repetirlo).
  String _lastChunk = '';

  bool get active => _active;

  /// Todo lo dicho hasta ahora.
  String get text =>
      [_committed, _partial].where((s) => s.trim().isNotEmpty).join(' ').trim();

  /// Empieza a escuchar. Devuelve false si no se pudo usar el micrófono.
  Future<bool> start({
    required String language,
    String initialText = '',
  }) async {
    _language = language;
    if (!_ready) {
      _ready = await _speech.initialize(
        onStatus: _onStatus,
        onError: (_) => _restartSoon(),
      );
    }
    if (!_ready) return false;
    _committed = initialText.trim();
    _partial = '';
    _lastChunk = '';
    _active = true;
    notifyListeners();
    await _listen();
    return true;
  }

  Future<void> _listen() async {
    if (!_active || _speech.isListening) return;
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: _language.replaceAll('-', '_'),
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 30),
        cancelOnError: false,
      ),
      onResult: (result) {
        // A veces el resultado final de un tramo llega después de que ya se
        // guardó al reiniciar: no se repite.
        if (_lastChunk.isNotEmpty &&
            result.recognizedWords.trim() == _lastChunk &&
            _committed.endsWith(_lastChunk)) {
          return;
        }
        _partial = result.recognizedWords;
        if (result.finalResult) {
          _lastChunk = _partial.trim();
          _committed = [
            _committed,
            _partial,
          ].where((s) => s.trim().isNotEmpty).join(' ').trim();
          _partial = '';
        }
        notifyListeners();
      },
    );
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _restartSoon();
    }
  }

  /// Si el usuario no terminó, se vuelve a escuchar.
  void _restartSoon() {
    if (!_active) return;
    if (_partial.isNotEmpty) {
      _lastChunk = _partial.trim();
      _committed = [_committed, _partial].join(' ').trim();
      _partial = '';
    }
    Future<void>.delayed(const Duration(milliseconds: 250), _listen);
  }

  /// Deja de escuchar y devuelve todo lo dicho.
  Future<String> finish() async {
    _active = false;
    await _speech.stop();
    final result = text;
    _committed = '';
    _partial = '';
    notifyListeners();
    return result;
  }

  Future<void> cancel() async {
    _active = false;
    await _speech.cancel();
    _committed = '';
    _partial = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _active = false;
    _speech.cancel();
    super.dispose();
  }
}
