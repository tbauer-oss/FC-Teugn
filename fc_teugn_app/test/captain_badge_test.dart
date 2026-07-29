import 'package:fc_teugn_app/core/widgets/captain_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a clear C marker with a captain tooltip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: CaptainBadge()),
        ),
      ),
    );

    expect(find.text('C'), findsOneWidget);
    expect(find.byTooltip(CaptainBadge.tooltip), findsOneWidget);
  });
}
