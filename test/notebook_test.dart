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

  test('la libreta se guarda, se tacha y vuelve a cargar', () async {
    final store = MemorySettingsStore();
    final s = AppSettings(store, MemoryKeyStore());
    await s.addNotes(['Pan', 'Leche']);
    await s.setNoteDone(s.notes.first, true);
    final again = AppSettings(store, MemoryKeyStore());
    await again.load(const ['claude']);
    expect(again.notes.map((n) => (n.text, n.done)), [
      ('Pan', true),
      ('Leche', false),
    ]);
    expect(again.exportPrefs(const ['claude']), contains('libreta'));
  });

  testWidgets('libreta: anotar varias y tachar una', (tester) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await tester.pumpWidget(MaterialApp(home: NotebookPage(settings: s)));
    await tester.enterText(
      find.byKey(const Key('notebook-input')),
      'uno pan dos leche',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('✓ Anoté 2 cosas en la libreta.'), findsOneWidget);
    expect(find.text('PARA HACER (2)'), findsOneWidget);
    await tester.tap(find.text('Pan'));
    await tester.pumpAndSettle();
    expect(find.text('HECHOS (1)'), findsOneWidget);
    expect(s.notes.firstWhere((n) => n.text == 'Pan').done, isTrue);
  });
}
