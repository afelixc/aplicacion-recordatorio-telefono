import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/app.dart';

void main() {
  testWidgets('Muestra las cuatro pestañas y cambia entre ellas', (tester) async {
    await tester.pumpWidget(const RecordameApp());

    expect(find.text('Recordame'), findsOneWidget);
    for (final label in ['Chat', 'Almanaque', 'Listado', 'Configuración']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Listado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('etapa 2'), findsOneWidget);
  });
}
