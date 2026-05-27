import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GTAudiobookApp());
    expect(find.text('GT听书'), findsOneWidget);
  });
}
