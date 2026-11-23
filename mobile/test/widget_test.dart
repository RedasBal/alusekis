import 'package:flutter_test/flutter_test.dart';

import 'package:alusekis/main.dart';

void main() {
  testWidgets('Programa pasileidžia', (WidgetTester tester) async {
    await tester.pumpWidget(const AlusekisApp());
    expect(find.text('Alusekis'), findsWidgets);
  });
}
