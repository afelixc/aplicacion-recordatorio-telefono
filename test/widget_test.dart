import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:recordame/app.dart';
import 'package:recordame/core/settings.dart';
import 'package:recordame/features/ai/ai_provider.dart';
import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/usage.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/core/palette.dart';
import 'package:recordame/features/reminders/reminders_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  Future<MemoryReminderRepository> pumpApp(
    WidgetTester tester, [
    List<Reminder> initial = const [],
  ]) async {
    final repo = MemoryReminderRepository(initial);
    final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await tester.pumpWidget(RecordameApp(reminders: repo, settings: settings));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('Muestra las cuatro pestañas', (tester) async {
    await pumpApp(tester);
    expect(find.text('TE RECORDARÉ'), findsOneWidget);
    expect(find.text('Tu plan:'), findsOneWidget);
    for (final label in ['Chat', 'Almanaque', 'Listado', 'Configuración']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('Carga un recordatorio desde el chat y aparece en el listado', (
    tester,
  ) async {
    final repo = await pumpApp(tester);

    await tester.enterText(
      find.byKey(const Key('reminder-title')),
      'Lavar el auto',
    );
    await tester.ensureVisible(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Guardado ✓ "Lavar el auto"'), findsOneWidget);
    expect((await repo.watchAll().first).single.title, 'Lavar el auto');

    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    expect(find.text('Lavar el auto'), findsOneWidget);
  });

  testWidgets('No deja guardar sin título', (tester) async {
    final repo = await pumpApp(tester);
    await tester.ensureVisible(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();
    expect(find.text('Escribí qué recordar'), findsOneWidget);
    expect(await repo.watchAll().first, isEmpty);
  });

  testWidgets('Marca como hecho y borra desde el listado', (tester) async {
    final due = DateTime.now().add(const Duration(days: 1));
    final repo = await pumpApp(tester, [
      Reminder(title: 'Pagar la luz', dueAt: due),
      Reminder(
        title: 'Sacar la basura',
        dueAt: due.add(const Duration(hours: 1)),
      ),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Todos ('));
    await tester.pumpAndSettle();

    // Marcar "Pagar la luz" como hecho: sale de Pendientes y aparece en Hechos.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Pagar la luz'), findsNothing);
    await tester.tap(find.text('Hechos'));
    await tester.pumpAndSettle();
    expect(find.text('Pagar la luz'), findsOneWidget);

    // Borrar "Sacar la basura".
    await tester.tap(find.text('Pendientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Sacar la basura'), findsNothing);
    expect((await repo.watchAll().first).length, 1);
  });

  testWidgets('Edita un recordatorio', (tester) async {
    final repo = await pumpApp(tester, [
      Reminder(
        title: 'Turno',
        dueAt: DateTime.now().add(const Duration(days: 2)),
      ),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Todos ('));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reminder-title')),
      'Turno con el dentista',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Turno con el dentista'), findsOneWidget);
    expect((await repo.watchAll().first).single.title, 'Turno con el dentista');
  });

  testWidgets('Carga un recordatorio que se repite varios días por semana', (
    tester,
  ) async {
    final repo = await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('reminder-title')), 'Gimnasio');

    await tester.tap(find.byKey(const Key('reminder-repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las semanas').last);
    await tester.pumpAndSettle();

    // Viene marcado el día elegido; sumar lunes y jueves (si no estaban).
    for (final day in ['Lu', 'Ju']) {
      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, day),
      );
      if (!chip.selected) {
        await tester.tap(find.widgetWithText(FilterChip, day));
        await tester.pumpAndSettle();
      }
    }
    await tester.ensureVisible(find.text('Guardar recordatorio'));
    await tester.ensureVisible(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar recordatorio'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchAll().first).single;
    expect(saved.recurrence.kind, RepeatKind.weekly);
    expect(
      saved.recurrence.weekdays,
      containsAll([DateTime.monday, DateTime.thursday]),
    );
    expect(
      find.textContaining('Guardado ✓ "Gimnasio", Todos los'),
      findsOneWidget,
    );
  });

  testWidgets('El almanaque muestra los recordatorios del día elegido', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Reminder(
        title: 'Turno médico',
        dueAt: DateTime(now.year, now.month, now.day, 23, 30),
      ),
    ]);
    await tester.tap(find.text('Almanaque'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Turno médico'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Turno médico'), findsOneWidget);
    expect(find.text('23:30'), findsOneWidget);
  });

  testWidgets('Modo IA: escribe, la IA arma el recordatorio y queda activo', (
    tester,
  ) async {
    final repo = MemoryReminderRepository();
    final store = MemorySettingsStore();
    final settings = AppSettings(
      store,
      MemoryKeyStore({'claude': 'sk-ant-prueba'}),
    );
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final date =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final fake = _FakeProvider(
      '{"ok":true,"title":"Lavar el auto","date":"$date","time":"09:00",'
      '"repeat":"none","weekdays":[],"dates":[],"message":"Listo"}',
    );
    final usage = MemoryUsageRepository();
    await tester.pumpWidget(
      RecordameApp(
        reminders: repo,
        settings: settings,
        usage: usage,
        aiProviderOverride: fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-input')),
      'Recordame mañana a las 9 lavar el auto',
    );
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(fake.lastUser, 'Recordame mañana a las 9 lavar el auto');
    final used = (await usage.watchSince(DateTime(2000)).first).single;
    expect(used.inputTokens, 1000);
    expect(used.outputTokens, 200);
    // Queda guardado y activo sin confirmar, con Modificar y Cancelar.
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Modificar'), findsOneWidget);
    final saved = (await repo.watchAll().first).single;
    expect(saved.title, 'Lavar el auto');
    expect(
      saved.dueAt,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
    );

    // Prioridad y "sonar en silencio", debajo de los botones.
    expect(saved.priority, ReminderPriority.normal);
    await tester.ensureVisible(find.byKey(const Key('priority-alta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('priority-alta')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('priority-loud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('priority-loud')));
    await tester.pumpAndSettle();
    final changed = (await repo.watchAll().first).single;
    expect(changed.priority, ReminderPriority.alta);
    expect(changed.loud, isTrue);

    // Cancelar lo borra; "Volver a activarlo" lo recupera.
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await repo.watchAll().first, isEmpty);
    expect(find.text('Cancelado'), findsOneWidget);
    await tester.ensureVisible(find.text('Volver a activarlo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver a activarlo'));
    await tester.pumpAndSettle();
    expect((await repo.watchAll().first).single.title, 'Lavar el auto');

    // En "Chat completo" está toda la conversación.
    await tester.tap(find.text('Chat completo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Recordame mañana a las 9 lavar el auto', skipOffstage: false),
      findsOneWidget,
    );

    // El chat queda guardado: al volver a abrir la app sigue estando.
    final reopened = AppSettings(store, MemoryKeyStore());
    await reopened.load(['claude']);
    expect(
      reopened.chatHistory.map((e) => e.text),
      contains('Recordame mañana a las 9 lavar el auto'),
    );
    expect(reopened.chatHistory.first.mine, isTrue);
  });

  testWidgets('dos recordatorios en un mensaje: guarda el completo y '
      'pregunta por el otro', (tester) async {
    final repo = MemoryReminderRepository();
    final settings = AppSettings(
      MemorySettingsStore(),
      MemoryKeyStore({'claude': 'sk-ant-prueba'}),
    );
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final date =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    String item(String title, {bool ok = true, String time = '09:00'}) =>
        '{"ok":$ok,"title":"$title","date":"${ok ? date : ''}",'
        '"time":"$time","repeat":"none","weekdays":[],"dates":[],'
        '"in_minutes":0,"message":"${ok ? 'Listo' : '¿Cuándo lo de la pelota?'}"}';
    final fake = _FakeProvider(
      '{"reminders":[${item('Lente')},${item('Pelota', ok: false)}],'
      '"message":"Listo"}',
      [
        // Al responder, la IA vuelve a mandar los dos: Lente no se repite.
        '{"reminders":[${item('Lente')},${item('Pelota', time: '18:00')}],'
            '"message":"Listo"}',
      ],
    );
    await tester.pumpWidget(
      RecordameApp(
        reminders: repo,
        settings: settings,
        aiProviderOverride: fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-input')),
      'Mañana a las 9 lente, y pelota',
    );
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect((await repo.watchAll().first).single.title, 'Lente');
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('¿Cuándo lo de la pelota?'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat-input')), 'a las 18');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(fake.lastUser, contains('no los vuelvas a crear: lente'));
    final all = await repo.watchAll().first;
    expect(all.map((r) => r.title), unorderedEquals(['Lente', 'Pelota']));
    expect(all.firstWhere((r) => r.title == 'Pelota').dueAt.hour, 18);
  });

  testWidgets('Chat: "Empezar de nuevo" olvida la pregunta pendiente', (
    tester,
  ) async {
    final repo = MemoryReminderRepository();
    final settings = AppSettings(
      MemorySettingsStore(),
      MemoryKeyStore({'claude': 'sk-ant-prueba'}),
    );
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    const ask =
        '{"reminders":[{"ok":false,"title":"","date":"","time":"",'
        '"repeat":"none","weekdays":[],"dates":[],"in_minutes":0,'
        '"message":"¿Cuándo?"}],"message":"¿Cuándo?"}';
    final fake = _FakeProvider(ask, [ask, ask]);
    await tester.pumpWidget(
      RecordameApp(
        reminders: repo,
        settings: settings,
        aiProviderOverride: fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat-input')), 'descargar');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-input')), 'eh');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    // No se anida "Pedido anterior" dentro de otro.
    await tester.enterText(find.byKey(const Key('chat-input')), 'mmm');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect('Pedido anterior'.allMatches(fake.lastUser!).length, 1);
    expect(fake.lastUser, contains('Después dijo: eh'));

    await tester.tap(find.byKey(const Key('start-over')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-input')), 'nuevo');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(fake.lastUser, 'nuevo');
  });

  testWidgets('Ejemplos: se leen, pero tocarlos no crea nada', (tester) async {
    final repo = MemoryReminderRepository();
    final settings = AppSettings(
      MemorySettingsStore(),
      MemoryKeyStore({'claude': 'sk-ant-prueba'}),
    );
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    final fake = _FakeProvider('{}');
    await tester.pumpWidget(
      RecordameApp(
        reminders: repo,
        settings: settings,
        aiProviderOverride: fake,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cargar a mano\nrecordatorios'), findsOneWidget);
    expect(find.text('Libreta'), findsOneWidget);
    expect(find.text('Todo hecho ✓'), findsOneWidget);
    await tester.tap(find.text('Ejemplos'));
    await tester.pumpAndSettle();
    expect(find.text('Ejemplos y formas de pedirlo'), findsOneWidget);
    expect(find.text('Una sola vez'), findsOneWidget);
    await tester.tap(find.textContaining('Mañana a las 20 llamar a Juan'));
    await tester.pumpAndSettle();
    expect(fake.lastUser, isNull);
    expect(await repo.watchAll().first, isEmpty);
  });

  testWidgets('Pendientes: filtra los de hoy y los pasados', (tester) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Reminder(
        title: 'Ayer vencido',
        dueAt: now.subtract(const Duration(days: 1)),
      ),
      Reminder(title: 'Para mañana', dueAt: now.add(const Duration(days: 1))),
      Reminder(
        title: 'Hoy a la noche',
        dueAt: DateTime(now.year, now.month, now.day, 23, 59),
      ),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    // Arranca en "Hoy".
    expect(find.text('Hoy (1)'), findsOneWidget);
    expect(find.text('Hoy a la noche'), findsOneWidget);
    expect(find.text('Para mañana'), findsNothing);
    expect(find.text('Todos (3)'), findsOneWidget);

    await tester.tap(find.text('Pasados (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Ayer vencido'), findsOneWidget);
    expect(find.text('Para mañana'), findsNothing);
    expect(find.text('Reprogramar'), findsOneWidget);

    await tester.tap(find.text('Todos (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Hoy a la noche'), findsOneWidget);
    expect(find.text('Para mañana'), findsOneWidget);
  });

  test('buscar: sin tildes, mayúsculas ni orden', () {
    const t = 'Mandar un mensaje a Fabricio Gandini, tema puerta';
    expect(matchesSearch(t, ''), isTrue);
    expect(matchesSearch(t, 'gandini'), isTrue);
    expect(matchesSearch(t, 'PUERTA fabricio'), isTrue);
    expect(matchesSearch('Llamar a Martín', 'martin'), isTrue);
    expect(matchesSearch(t, 'ventana'), isFalse);
  });

  testWidgets('Listado: buscador y colores de Todos', (tester) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Reminder(
        title: 'Mensaje a Fabricio Gandini, tema puerta',
        dueAt: now.add(const Duration(days: 2)),
      ),
      Reminder(title: 'Pagar la luz', dueAt: now.add(const Duration(days: 3))),
    ]);
    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();

    // En Pendientes → Hoy no está: ofrece buscar en Todos.
    await tester.enterText(find.byKey(const Key('search')), 'gandini');
    await tester.pumpAndSettle();
    expect(find.textContaining('Acá no hay nada'), findsOneWidget);
    expect(find.text('Todos (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-all')));
    await tester.pumpAndSettle();
    expect(
      find.text('Mensaje a Fabricio Gandini, tema puerta'),
      findsOneWidget,
    );
    expect(find.text('Pagar la luz'), findsNothing);

    // Borrar la búsqueda vuelve a mostrar todo.
    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('Pagar la luz'), findsOneWidget);

    // Colores: el botón lleva a Configuración → Colores; verde para los
    // pendientes de día.
    await tester.tap(find.byKey(const Key('list-colors')));
    await tester.pumpAndSettle();
    expect(find.text('ESTÁS PINTANDO LOS COLORES DE DÍA'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('pend-verde')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pend-verde')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final card = tester.widget<Card>(
      find
          .ancestor(of: find.text('Pagar la luz'), matching: find.byType(Card))
          .first,
    );
    expect(card.color, softColor('verde').dayFill);
  });

  testWidgets('Colores: día y noche por separado, fondo y almanaque', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await tester.pumpWidget(
      RecordameApp(reminders: MemoryReminderRepository(), settings: settings),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colores'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Siempre noche'));
    // Siempre noche: la app pasa a oscuro y se pinta la solapa de noche.
    await tester.tap(find.text('Siempre noche'));
    await tester.pumpAndSettle();
    expect(settings.dayNight, DayNight.night);
    expect(find.text('ESTÁS PINTANDO LOS COLORES DE NOCHE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bg-lavanda')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('main-bordo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-bordo')));
    await tester.pumpAndSettle();
    expect(settings.nightColors.background, 'lavanda');
    expect(settings.nightColors.main, 'bordo');
    // Los de día no se tocaron.
    expect(settings.dayColors, const ColorSet());

    // Ícono: se guarda la elección (en la prueba no hay Android).
    await tester.ensureVisible(find.byKey(const Key('icon-rojo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon-rojo')));
    await tester.pumpAndSettle();
    expect(settings.appIconId, 'rojo');
  });

  test('Colores: se guardan y se leen; migra los del listado viejo', () async {
    final store = MemorySettingsStore();
    await store.write('color_pending', 'verde');
    await store.write('color_done', 'rosa');
    final a = AppSettings(store, MemoryKeyStore());
    await a.load(const []);
    expect(a.dayColors.pending, 'verde');
    expect(a.nightColors.done, 'rosa');

    await a.setColors(
      a.dayColors.copyWith(background: 'cremita', today: 'rojo'),
      night: false,
    );
    await a.setDayNight(DayNight.day);
    final b = AppSettings(store, MemoryKeyStore());
    await b.load(const []);
    expect(b.dayColors.background, 'cremita');
    // El formato viejo (fondo sí/no) se entiende como cremita.
    expect(ColorSet.decode('{"fondo":true}').background, 'cremita');
    expect(b.dayColors.today, 'rojo');
    expect(b.dayColors.pending, 'verde');
    expect(b.dayNight, DayNight.day);
    expect(b.exportPrefs(const []).keys, contains('colores_noche'));
  });

  testWidgets('deslizar cambia de solapa y da la vuelta; el mes queda', (
    tester,
  ) async {
    await pumpApp(tester);
    final now = DateTime.now();
    String title(DateTime m) {
      final t = DateFormat('MMMM yyyy', 'es_AR').format(m);
      return t[0].toUpperCase() + t.substring(1);
    }

    final area = find.byKey(const Key('tab-swipe'));
    // Chat → Almanaque.
    await tester.flingFrom(
      tester.getTopLeft(area) + const Offset(400, 30),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(title(now)), findsOneWidget);
    // En el almanaque, deslizar no cambia el mes: pasa a Listado.
    await tester.flingFrom(
      tester.getTopLeft(area) + const Offset(400, 30),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(title(now)), findsNothing);
    expect(find.byKey(const Key('notebook-fab')), findsOneWidget);
    // Listado → Configuración → vuelve a Chat.
    await tester.flingFrom(
      tester.getTopLeft(area) + const Offset(400, 30),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    await tester.flingFrom(
      tester.getTopLeft(area) + const Offset(400, 30),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notebook-fab')), findsNothing);
    // Para el otro lado: Chat → Configuración.
    await tester.flingFrom(
      tester.getTopLeft(area) + const Offset(400, 30),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notebook-fab')), findsOneWidget);
  });

  testWidgets('la libreta flotante anota rápido sin salir del almanaque', (
    tester,
  ) async {
    final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await tester.pumpWidget(
      RecordameApp(reminders: MemoryReminderRepository(), settings: settings),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Almanaque'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook-fab')));
    await tester.pumpAndSettle();
    expect(find.text('Anotar en la libreta'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('notebook-input')),
      'Comprar filamento',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('notebook-send')));
    await tester.pumpAndSettle();
    expect(settings.folders.single.items.single.text, 'Comprar filamento');
    expect(find.text('1 pendiente'), findsWidgets);
  });

  testWidgets(
    'Tu plan: cambia entre Gratis y Con IA; la ayuda lleva a Configuración',
    (tester) async {
      final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
      await tester.pumpWidget(
        RecordameApp(reminders: MemoryReminderRepository(), settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Con IA'));
      await tester.pumpAndSettle();
      expect(settings.mode, UsageMode.ai);
      expect(find.text('Falta tu clave de IA.'), findsOneWidget);

      await tester.tap(find.byTooltip('¿Cómo funciona?'));
      await tester.pumpAndSettle();
      expect(find.text('¿Por qué hace falta una clave?'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Ir a Configuración'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Ir a Configuración'));
      await tester.pumpAndSettle();
      expect(find.text('Modo de uso'), findsOneWidget);
      expect(find.text('Inteligencia artificial'), findsOneWidget);
    },
  );

  testWidgets('En modo IA se pueden elegir los modelos de Claude', (
    tester,
  ) async {
    // Pantalla alta para que toda la configuración entre sin deslizar.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    await tester.pumpWidget(
      RecordameApp(reminders: MemoryReminderRepository(), settings: settings),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inteligencia artificial'));
    await tester.pumpAndSettle();
    // Los tres modelos se ven con su explicación; tocar uno lo elige al toque.
    expect(find.text('Haiku 5.5'), findsOneWidget);
    expect(find.text('Sonnet 5.5'), findsOneWidget);
    await tester.tap(find.text('Opus 5.5'));
    await tester.pumpAndSettle();
    expect(settings.modelFor('claude'), 'claude-opus-5-5');
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('Borrar la clave pide confirmación', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(
      MemorySettingsStore(),
      MemoryKeyStore({'claude': 'sk-ant-prueba'}),
    );
    await settings.load(['claude']);
    await settings.setMode(UsageMode.ai);
    await tester.pumpWidget(
      RecordameApp(
        reminders: MemoryReminderRepository(),
        settings: settings,
        aiProviderOverride: _FakeProvider('{}'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inteligencia artificial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar la clave?'), findsOneWidget);
    await tester.tap(find.text('No, dejarla'));
    await tester.pumpAndSettle();
    expect(settings.hasKey('claude'), isTrue);
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, borrar'));
    await tester.pumpAndSettle();
    expect(settings.hasKey('claude'), isFalse);
  });
}

class _FakeProvider implements AiProvider {
  _FakeProvider(this.answer, [this.later = const []]);

  final String answer;

  /// Respuestas para las consultas siguientes, en orden.
  final List<String> later;
  int _calls = 0;
  String? lastUser;

  @override
  String get id => 'claude';
  @override
  String get name => 'Prueba';
  @override
  String get defaultModel => 'modelo';
  @override
  List<(String, String)> get suggestedModels => const [];
  @override
  String get keyPrefix => '';
  @override
  String get keysUrl => '';
  @override
  String get billingUrl => '';
  @override
  List<String> get guideSteps => const [];

  @override
  Future<List<String>> listModels(String apiKey) async => ['modelo'];

  @override
  Future<AiResult> completeJson({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
  }) async {
    lastUser = user;
    final i = _calls++;
    final text = i == 0 || later.isEmpty
        ? answer
        : later[(i - 1).clamp(0, later.length - 1)];
    return AiResult(text, inputTokens: 1000, outputTokens: 200);
  }
}
