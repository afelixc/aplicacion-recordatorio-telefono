import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/features/chat/ai_chat.dart';

void main() {
  testWidgets('un mensaje largo se ve en 2 renglones y al tocarlo, entero', (
    tester,
  ) async {
    final long = List.filled(40, 'palabra').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: TapToExpand(long, maxLines: 2)),
        ),
      ),
    );
    Text text() => tester.widget<Text>(find.text(long));
    final closed = tester.getSize(find.byType(TapToExpand)).height;
    expect(text().maxLines, 2);

    await tester.tap(find.byType(TapToExpand));
    await tester.pumpAndSettle();
    expect(text().maxLines, isNull);
    expect(
      tester.getSize(find.byType(TapToExpand)).height,
      greaterThan(closed),
    );

    // Al volver a tocarlo se cierra.
    await tester.tap(find.byType(TapToExpand));
    await tester.pumpAndSettle();
    expect(text().maxLines, 2);
  });
}
