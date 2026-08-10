import 'package:fc_teugn_app/features/privacy/privacy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy center is complete and responsive on a phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: PrivacyInformationCenter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transparenz & Betroffenenrechte'), findsOneWidget);
    expect(
      find.text('Verantwortlicher & Datenschutzkontakt'),
      findsOneWidget,
    );
    expect(find.textContaining('info@fc-teugn.de'), findsOneWidget);
    expect(find.textContaining('fcteugn@web.de'), findsNothing);
    expect(
      find.text('Ihre Rechte nach der DSGVO', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('BayLDA öffnen', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
