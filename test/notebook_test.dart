import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/core/settings.dart';
import 'package:recordame/features/notebook/notebook_page.dart';
import 'package:recordame/features/notebook/notes.dart';

void main() {
  test('cuenta lo que falta hacer, con los ítems de adentro', () {
    final at = DateTime(2026);
    final f = NoteFolder(
      'Casa',
      items: [
        NoteItem(
          'Compras',
          at: at,
          sub: const [
            SubItem('pan', done: true),
            SubItem('leche'),
            SubItem('vino'),
          ],
        ),
        NoteItem('Llamar al plomero', at: at),
        NoteItem('Ya está', at: at, done: true),
        NoteItem(
          'Lista tildada',
          at: at,
          sub: const [SubItem('a', done: true)],
        ),
      ],
    );
    expect(f.toDo, 4);
    expect(notebookToDo([f, NoteFolder('Vacía')]), 4);
    expect(toDoLabel(0), 'Todo hecho ✓');
    expect(toDoLabel(4), '4 por hacer');
  });

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

  test('cuenta hasta 10 cosas dictadas', () {
    expect(
      splitNotes(
        'uno pan dos leche tres huevos cuatro yerba cinco azúcar seis fideos '
        'siete arroz ocho aceite nueve sal diez café',
      ),
      [
        'Pan',
        'Leche',
        'Huevos',
        'Yerba',
        'Azúcar',
        'Fideos',
        'Arroz',
        'Aceite',
        'Sal',
        'Café',
      ],
    );
  });

  testWidgets('editar una nota y armar una lista adentro', (tester) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('Casa', folderColors.first);
    await s.addNotes(f, ['Compras']);
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditPage(settings: s, folder: f, note: f.items.first),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('notebook-input')),
      'pan, leche, huevos',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('notebook-send')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-title')), 'Supermercado');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final n = f.items.single;
    expect(n.text, 'Supermercado');
    expect(n.sub.map((x) => x.text), ['Pan', 'Leche', 'Huevos']);
  });

  testWidgets('ítems de adentro: bajar, editar y se ven solo al abrir', (
    tester,
  ) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('Alejandro', folderColors.first);
    await s.addNotes(f, ['Compras']);
    await s.replaceNote(
      f,
      f.items.single,
      f.items.single.copyWith(sub: const [SubItem('Pan'), SubItem('Lehce')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditPage(settings: s, folder: f, note: f.items.single),
      ),
    );
    await tester.tap(find.byTooltip('Bajar').first);
    await tester.pumpAndSettle();
    expect(f.items.single.sub.map((x) => x.text), ['Lehce', 'Pan']);
    await tester.tap(find.byTooltip('Editar').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sub-edit')), 'Leche');
    await tester.tap(find.byKey(const Key('sub-edit-save')));
    await tester.pumpAndSettle();
    expect(f.items.single.sub.map((x) => x.text), ['Leche', 'Pan']);

    // En la carpeta, cerrada muestra "(0/2)" y al tocarla se despliega.
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPage(settings: s, folder: f),
      ),
    );
    expect(find.text('Compras  (0/2)'), findsOneWidget);
    expect(find.text('Leche'), findsNothing);
    await tester.tap(find.text('Compras  (0/2)'));
    await tester.pumpAndSettle();
    expect(find.text('Leche'), findsOneWidget);
  });

  testWidgets('tildar un ítem no cierra la nota y avisa si quedan cosas', (
    tester,
  ) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('General', folderColors.first);
    await s.addNotes(f, ['Compras']);
    await s.replaceNote(
      f,
      f.items.single,
      f.items.single.copyWith(sub: const [SubItem('Vino'), SubItem('Pan')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPage(settings: s, folder: f),
      ),
    );
    await tester.tap(find.text('Compras  (0/2)'));
    await tester.pumpAndSettle();
    // Checkbox 0 es la nota; 1 y 2, los ítems.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Pan'), findsOneWidget);
    await tester.tap(find.text('Pan'));
    await tester.pumpAndSettle();
    expect(find.text('Pan'), findsOneWidget);
    // Dar por hecha la nota con un ítem sin tildar: pregunta.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Fijate: quedaron cosas por hacer'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(f.items.single.done, isFalse);
  });

  testWidgets('buscador: lleva al ítem de adentro de una nota', (tester) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('General', folderColors.first);
    await s.addNotes(f, ['Compras']);
    await s.replaceNote(
      f,
      f.items.single,
      f.items.single.copyWith(sub: const [SubItem('Vino tinto')]),
    );
    await tester.pumpWidget(MaterialApp(home: NotebookPage(settings: s)));
    await tester.enterText(find.byKey(const Key('notebook-search')), 'vino');
    await tester.pumpAndSettle();
    expect(find.text('En General › Compras'), findsOneWidget);
    await tester.tap(find.text('Vino tinto'));
    await tester.pumpAndSettle();
    // Se abre la carpeta con la nota desplegada.
    expect(find.text('Vino tinto'), findsOneWidget);
    expect(find.text('Compras  (0/1)'), findsOneWidget);
  });

  testWidgets('buscador adentro de la carpeta', (tester) async {
    final s = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    final f = await s.addFolder('General', folderColors.first);
    await s.addNotes(f, ['Compras', 'Llamar a Ignacio']);
    await s.replaceNote(
      f,
      f.items.first,
      f.items.first.copyWith(sub: const [SubItem('Vino'), SubItem('Pan')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPage(settings: s, folder: f),
      ),
    );
    await tester.enterText(find.byKey(const Key('folder-search')), 'vino');
    await tester.pumpAndSettle();
    expect(find.text('Vino'), findsOneWidget);
    expect(find.text('Llamar a Ignacio'), findsNothing);
  });
}
