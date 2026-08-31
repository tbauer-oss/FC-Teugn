import 'package:fc_teugn_app/core/google_maps_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a Google Maps search URL with the complete address', () {
    final uri = googleMapsSearchUri(
      '  Sportplatzstraße 12, 93080 Pentling  ',
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['api'], '1');
    expect(
      uri.queryParameters['query'],
      'Sportplatzstraße 12, 93080 Pentling',
    );
  });

  testWidgets('map action remains readable on a narrow display',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 240),
            textScaler: TextScaler.linear(1.35),
          ),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: GoogleMapsAddressAction(
                address: 'Sportanlage am langen Gegnerweg 123, 93080 Pentling',
                compact: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Route zum Auswärtsspiel'), findsOneWidget);
    expect(find.byIcon(Icons.map_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
