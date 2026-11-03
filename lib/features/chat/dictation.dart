import 'dart:async';

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

  /// El último tramo que se guardó (para no repetirlo) y lo que había antes
  /// de él (para cambiarlo por una versión más completa del mismo tramo).
  String _lastChunk = '';
  String _beforeLast = '';

  /// Al tocar Enviar: espera las últimas palabras que todavía no llegaron.
  Completer<void>? _finalWaiter;

  /// Ya hay un reinicio en camino (Android avisa el corte dos o tres veces:
  /// "done", "notListening", error). Si se reiniciara dos veces, el segundo
  /// arranque borraría lo que se está diciendo en ese momento.
  bool _restarting = false;
  bool _starting = false;

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
    _beforeLast = '';
    _active = true;
    notifyListeners();
    await _listen();
    return true;
  }

  Future<void> _listen() async {
    _restarting = false;
    if (!_active || _starting || _speech.isListening) return;
    // Lo que quedó a medio escuchar del tramo anterior no se pierde.
    if (_partial.isNotEmpty) {
      _commit(_partial);
      _partial = '';
    }
    _starting = true;
    try {
      await _listenNow();
    } finally {
      _starting = false;
    }
  }

  Future<void> _listenNow() async {
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
        if (result.finalResult) {
          _partial = '';
          _commit(result.recognizedWords);
          _finalWaiter?.complete();
          _finalWaiter = null;
        } else {
          _partial = result.recognizedWords;
        }
        notifyListeners();
      },
    );
  }

  static String _plain(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _join(String a, String b) =>
      [a, b].where((s) => s.trim().isNotEmpty).join(' ').trim();

  /// Suma un tramo dicho. Android a veces manda el mismo tramo dos veces al
  /// reiniciar (igual, más corto o más completo): no se repite, y si llega
  /// más completo reemplaza al anterior.
  void _commit(String chunk) {
    chunk = chunk.trim();
    if (chunk.isEmpty) return;
    final now = _plain(chunk);
    final last = _plain(_lastChunk);
    if (last.isNotEmpty) {
      // Para los prefijos, tramos de varias palabras: "a" no es "a las 11".
      if (now == last || (now.length >= 8 && last.startsWith('$now '))) {
        return;
      }
      if (last.length >= 8 && now.startsWith('$last ')) {
        _committed = _join(_beforeLast, chunk);
        _lastChunk = chunk;
        return;
      }
    }
    _beforeLast = _committed;
    _committed = _join(_committed, chunk);
    _lastChunk = chunk;
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus) {
      _finalWaiter?.complete();
      _finalWaiter = null;
    }
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _restartSoon();
    }
  }

  /// Si el usuario no terminó, se vuelve a escuchar.
  void _restartSoon() {
    if (!_active) return;
    if (_partial.isNotEmpty) {
      _commit(_partial);
      _partial = '';
    }
    if (_restarting) return;
    _restarting = true;
    // Lo más rápido posible, para no perder palabras en el corte.
    Future<void>.delayed(const Duration(milliseconds: 80), _listen);
  }

  /// Deja de escuchar y devuelve todo lo dicho. Espera un momento las últimas
  /// palabras: si se toca Enviar enseguida de hablar, todavía no llegaron.
  Future<String> finish({
    Duration wait = const Duration(milliseconds: 1500),
  }) async {
    _active = false;
    final waiter = _finalWaiter = Completer<void>();
    await _speech.stop();
    await waiter.future.timeout(wait, onTimeout: () {});
    _finalWaiter = null;
    if (_partial.isNotEmpty) _commit(_partial);
    _partial = '';
    final result = text;
    _committed = '';
    _partial = '';
    _lastChunk = '';
    _beforeLast = '';
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
