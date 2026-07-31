import 'package:fc_teugn_app/features/players/widgets/digital_signature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens a large signature dialog and returns the signature',
      (tester) async {
    Map<String, dynamic>? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DigitalSignatureCapture(
            signatureData: null,
            onChanged: (value) => captured = value,
          ),
        ),
      ),
    );

    expect(find.text('Unterschrift hinzufügen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-signature-dialog')));
    await tester.pumpAndSettle();

    expect(find.text('Digital unterschreiben'), findsOneWidget);
    expect(find.text('Neu beginnen'), findsOneWidget);
    expect(find.text('Unterschrift übernehmen'), findsOneWidget);

    final pad = find.byKey(const ValueKey('digital-signature-pad'));
    expect(pad, findsOneWidget);
    expect(tester.getSize(pad).height, greaterThan(200));

    final center = tester.getCenter(pad);
    final gesture = await tester.startGesture(center.translate(-80, 0));
    for (var index = 1; index <= 12; index++) {
      await gesture.moveTo(
        center.translate(-80 + (index * 12), index.isEven ? -20 : 20),
      );
    }
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('accept-signature')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['strokes'], isNotEmpty);
    expect(find.text('Digital unterschreiben'), findsNothing);
  });

  testWidgets('keeps the dialog open when no signature was drawn',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DigitalSignatureCapture(
            signatureData: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-signature-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept-signature')));
    await tester.pump();

    expect(
      find.text('Bitte zuerst im großen Unterschriftsfeld unterschreiben.'),
      findsOneWidget,
    );
    expect(find.text('Digital unterschreiben'), findsOneWidget);
  });
}
