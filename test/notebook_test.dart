import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/core/settings.dart';
import 'package:recordame/features/notebook/notebook_page.dart';
import 'package:recordame/features/notebook/notes.dart';

void main() {
  test('separa lo dictado en renglones', () {
    expect(
      splitNotes(
        'cargame estos ítems uno llamar al contador dos comprar tornillos '
        'tres pagar la luz',
      ),
      ['Llamar al contador', 'Comprar tornillos', 'Pagar la luz'],
    );
    expect(
      splitNotes(
        'me faltó llevar el auto al taller y también pedir presupuesto de chapa',
      ),
      ['Llevar el auto al taller', 'Pedir presupuesto de chapa'],
    );
    expect(splitNotes('1. pan\n2. leche'), ['Pan', 'Leche']);
    expect(splitNotes('Pasar por lo de Juan'), ['Pasar por lo de Juan']);
    // "una" dentro de la frase no corta: solo al principio de un ítem.
    expect(splitNotes('comprar una lámpara'), ['Comprar una lámpara']);
    // Contar en orden: "dos kilos" no corta.
    expect(splitNotes('comprar dos kilos de pan'), [
      'Comprar dos kilos de pan',
    ]);
    expect(splitNotes('primero ir al banco segundo comprar dos sillas'), [
      'Ir al banco',
      'Comprar dos sillas',
    ]);
  });

  test('la libreta de antes pasa a la carpeta General', () async {
    final store = MemorySettingsStore();
    await store.write(
      'libreta',
      '[{"t":"Pan","d":true,"at":"2026-11-01T10:00:00"},'
          '{"t":"Leche","at":"2026-11-01T10:00:00"}]',
    );
    final s = AppSettings(store, MemoryKeyStore());
    await s.load(const ['claude']);
    expect(s.folders.single.name, 'General');
    expect(s.folders.single.items.map((n) => n.text), ['Leche', 'Pan']);
  });

  test('carpetas: anotar, tachar, mover y volver a cargar', () async {
    final store = MemorySettingsStore();
    final s = AppSettings(store, MemoryKeyStore());
    final f = await s.addFolder('Impresora', folderColors[1]);
    await s.addNotes(f, ['Tóner', 'Cabezal', 'Papel']);
    await s.setNoteDone(f, f.items.first, true);
    await s.moveNote(f, f.pending.last, -1);
    await s.addNotes(f, ['Cable']);
    final again = AppSettings(store, MemoryKeyStore());
    await again.load(const ['claude']);
    final g = again.folders.single;
    expect(g.name, 'Impresora');
    expect(g.color, folderColors[1]);
    expect(g.items.map((n) => (n.text, n.done)), [
      ('Papel', false),
      ('Cabezal', false),
      ('Cable', false),
      ('Tóner', true),
    ]);
    expect(again.exportPrefs(const ['claude']), contains('libreta'));
  });

  testWidgets('carpeta: anotar con ✓ y tildar solo con el cuadradito', (
    tester,
  ) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('Auto', folderColors.first);
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPage(settings: s, folder: f),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('notebook-input')),
      'uno taller dos patente',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('notebook-send')));
    await tester.pumpAndSettle();
    expect(find.text('✓ Anoté 2 cosas en Auto.'), findsOneWidget);
    expect(find.text('PARA HACER (2)'), findsOneWidget);
    // Tocar el texto no lo da por hecho: muestra subir y bajar.
    await tester.tap(find.text('Taller'));
    await tester.pumpAndSettle();
    expect(f.items.first.done, isFalse);
    expect(find.byTooltip('Bajar'), findsOneWidget);
    await tester.tap(find.byTooltip('Bajar'));
    await tester.pumpAndSettle();
    expect(f.items.map((n) => n.text), ['Patente', 'Taller']);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('HECHOS (1)'), findsOneWidget);
  });

  testWidgets('buscador: encuentra carpetas y cosas', (tester) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('Impresora', folderColors.first);
    await s.addNotes(f, ['Cambiar el tóner']);
    await s.addFolder('Auto', folderColors.first);
    await tester.pumpWidget(MaterialApp(home: NotebookPage(settings: s)));
    await tester.enterText(find.byKey(const Key('notebook-search')), 'toner');
    await tester.pumpAndSettle();
    expect(find.text('Cambiar el tóner'), findsOneWidget);
    expect(find.text('En Impresora'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
  });
}
