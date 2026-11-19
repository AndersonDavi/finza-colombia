import 'package:budget/widgets/aiMarkdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("draws bold, lists and tables without the symbols",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiMarkdownText("""## Resumen
Tienes **3 cuentas** y *pocos* gastos.
- Bancolombia
1. Primero
| Categoría | Total |
|---|---|
| Mercado | \$500.000 |"""),
      ),
    ));
    expect(find.textContaining("**"), findsNothing);
    expect(find.textContaining("|"), findsNothing);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining("Mercado", findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
