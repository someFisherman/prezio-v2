import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prezio_v2/app.dart';

void main() {
  testWidgets('App should start', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PrezioApp(),
      ),
    );

    expect(find.text('Prezio'), findsOneWidget);
  });
}
