import 'dart:convert';

/// Un ítem de la lista que hay adentro de una nota (por ejemplo, las
/// compras: pan, leche…).
class SubItem {
  const SubItem(this.text, {this.done = false});

  final String text;
  final bool done;

  Map<String, dynamic> toJson() => {'t': text, if (done) 'd': true};

  static SubItem fromJson(Map<String, dynamic> j) =>
      SubItem('${j['t']}', done: j['d'] == true);
}

/// Una nota de la libreta. Puede tener una lista adentro ([sub]) y un aviso
/// ([alarm]).
class NoteItem {
  const NoteItem(
    this.text, {
    this.done = false,
    required this.at,
    this.alarm,
    this.sub = const [],
  });

  final String text;
  final bool done;
  final DateTime at;

  /// Si se le puso aviso con la campanita: cuándo suena.
  final DateTime? alarm;

  final List<SubItem> sub;

  NoteItem copyWith({
    String? text,
    bool? done,
    DateTime? alarm,
    List<SubItem>? sub,
  }) => NoteItem(
    text ?? this.text,
    done: done ?? this.done,
    at: at,
    alarm: alarm ?? this.alarm,
    sub: sub ?? this.sub,
  );

  Map<String, dynamic> toJson() => {
    't': text,
    if (done) 'd': true,
    'at': at.toIso8601String(),
    if (alarm != null) 'al': alarm!.toIso8601String(),
    if (sub.isNotEmpty) 's': [for (final x in sub) x.toJson()],
  };

  static NoteItem fromJson(Map<String, dynamic> j) => NoteItem(
    '${j['t']}',
    done: j['d'] == true,
    at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
    alarm: j['al'] == null ? null : DateTime.tryParse('${j['al']}'),
    sub: [
      for (final e in (j['s'] as List? ?? const []))
        SubItem.fromJson(e as Map<String, dynamic>),
    ],
  );
}

/// Colores para las carpetas (ARGB).
const folderColors = <int>[
  0xFFE0A800, // amarillo
  0xFF2F6FB3, // azul
  0xFF2E8B57, // verde
  0xFFD9534F, // rojo
  0xFF8E5CC2, // violeta
  0xFFE67E22, // naranja
  0xFF16A2B8, // celeste
  0xFF7F8C8D, // gris
];

/// Una carpeta de la libreta (Impresora, Auto…). Primero los pendientes, en
/// el orden que eligió el usuario, y después los hechos.
class NoteFolder {
  NoteFolder(this.name, {this.color = 0xFFE0A800, List<NoteItem>? items})
    : items = items ?? [];

  String name;
  int color;
  final List<NoteItem> items;

  List<NoteItem> get pending => [
    for (final n in items)
      if (!n.done) n,
  ];
  List<NoteItem> get done => [
    for (final n in items)
      if (n.done) n,
  ];

  Map<String, dynamic> toJson() => {
    'n': name,
    'c': color,
    'i': [for (final n in items) n.toJson()],
  };

  static NoteFolder fromJson(Map<String, dynamic> j) => NoteFolder(
    '${j['n']}',
    color: (j['c'] as num?)?.toInt() ?? folderColors.first,
    items: [
      for (final e in (j['i'] as List? ?? const []))
        NoteItem.fromJson(e as Map<String, dynamic>),
    ],
  );

  /// Lo guardado: `{"carpetas": [...]}`. La primera versión guardaba una
  /// lista suelta de cosas: va a una carpeta "General".
  static List<NoteFolder> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw);
    if (data is List) {
      if (data.isEmpty) return [];
      final items = [
        for (final e in data) NoteItem.fromJson(e as Map<String, dynamic>),
      ];
      return [
        NoteFolder(
          'General',
          items: [
            ...items.where((n) => !n.done),
            ...items.where((n) => n.done),
          ],
        ),
      ];
    }
    return [
      for (final e in (data['carpetas'] as List? ?? const []))
        NoteFolder.fromJson(e as Map<String, dynamic>),
    ];
  }

  static String encodeAll(List<NoteFolder> folders) => jsonEncode({
    'carpetas': [for (final f in folders) f.toJson()],
  });
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
  ['once', 'undécimo', '11'],
  ['doce', 'duodécimo', '12'],
  ['trece', '13'],
  ['catorce', '14'],
  ['quince', '15'],
  ['dieciséis', 'dieciseis', '16'],
  ['diecisiete', '17'],
  ['dieciocho', '18'],
  ['diecinueve', '19'],
  ['veinte', '20'],
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
