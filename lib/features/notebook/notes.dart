/// Una cosa anotada en la libreta (sin fecha ni aviso).
class NoteItem {
  const NoteItem(this.text, {this.done = false, required this.at});

  final String text;
  final bool done;
  final DateTime at;

  NoteItem copyWith({bool? done}) =>
      NoteItem(text, done: done ?? this.done, at: at);

  Map<String, dynamic> toJson() => {
    't': text,
    if (done) 'd': true,
    'at': at.toIso8601String(),
  };

  static NoteItem fromJson(Map<String, dynamic> j) => NoteItem(
    '${j['t']}',
    done: j['d'] == true,
    at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
  );
}

// Contando: "uno … dos … tres", "primero … segundo", "1. … 2)".
const _counting = [
  ['uno', 'primero', '1'],
  ['dos', 'segundo', '2'],
  ['tres', 'tercero', '3'],
  ['cuatro', 'cuarto', '4'],
  ['cinco', 'quinto', '5'],
  ['seis', 'sexto', '6'],
  ['siete', 'séptimo', '7'],
  ['ocho', 'octavo', '8'],
  ['nueve', 'noveno', '9'],
  ['diez', 'décimo', '10'],
];

// "… y también …", "… y después …", "… y además …".
final _joiners = RegExp(
  r'\s+y\s+(?:también|tambien|después|despues|además|ademas)\s+',
  caseSensitive: false,
);

/// Corta en "uno … dos … tres" solo si se está contando en orden: así
/// "comprar dos kilos de pan" no se parte.
List<String> _splitCounting(String text) {
  RegExp word(int n) => RegExp(
    '(?:^|\\s)(?:${_counting[n].join('|')})(?=[\\s.,:;)\\-]|\$)[.,:;)\\-]?',
    caseSensitive: false,
  );
  final first = word(0).firstMatch(text);
  if (first == null || !word(1).hasMatch(text.substring(first.end))) {
    return [text];
  }
  final parts = <String>[if (first.start > 0) text.substring(0, first.start)];
  var from = first.end;
  for (var n = 1; n < _counting.length; n++) {
    final next = word(n).firstMatch(text.substring(from));
    if (next == null) break;
    parts.add(text.substring(from, from + next.start));
    from += next.end;
  }
  parts.add(text.substring(from));
  return parts;
}

final _intro = RegExp(
  r'^\s*(?:che[\s,]+)?(?:(?:cargame|cargá|carga|anotame|anotá|anota|'
  r'agregame|agregá|apuntame)(?:\s+(?:todos\s+)?(?:estos|estas)\s+'
  r'(?:ítems|items|cosas))?|me falt[oó](?:\s+hacer)?|tengo que)\s*[:,]?\s*',
  caseSensitive: false,
);

/// Separa lo dictado o escrito en renglones: "uno llamar al contador dos
/// comprar tornillos" → ["Llamar al contador", "Comprar tornillos"].
/// Lo hace el teléfono, sin la IA (no gasta saldo).
List<String> splitNotes(String text) {
  text = text.replaceFirst(_intro, '');
  final parts = <String>[];
  final pieces = [
    for (final line in text.split('\n'))
      for (final p in _splitCounting(
        // Lista escrita: "1. pan", "- leche".
        line.replaceFirst(RegExp(r'^\s*(?:\d+[.)\-]|[-•*])\s*'), ''),
      ))
        ...p.split(_joiners),
  ];
  for (final piece in pieces) {
    for (var s in piece.split(RegExp(r';|,\s*(?=\S)'))) {
      s = s.trim().replaceFirst(
        RegExp(r'^(?:y|e|,|\.)\s+', caseSensitive: false),
        '',
      );
      s = s.replaceAll(RegExp(r'[\s.,;:]+$'), '').trim();
      if (s.length < 2) continue;
      parts.add(s[0].toUpperCase() + s.substring(1));
    }
  }
  return parts;
}
