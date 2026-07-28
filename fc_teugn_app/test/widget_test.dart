import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/app.dart';

void main() {
  testWidgets('shows the FC Teugn login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FCTeugnApp()));
    await tester.pumpAndSettle();

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
  });
}
