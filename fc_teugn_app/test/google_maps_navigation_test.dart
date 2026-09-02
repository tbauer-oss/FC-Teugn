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

  test('postal away address always wins over an ambiguous venue name', () {
    expect(
      resolvedMatchNavigationAddress(
        isAway: true,
        address: 'Am Waldstadion 1, 84085 Langquaid',
        location: 'Waldstadion',
      ),
      'Am Waldstadion 1, 84085 Langquaid',
    );
    expect(
      resolvedMatchNavigationAddress(
        isAway: false,
        address: 'Am Waldstadion 1, 84085 Langquaid',
        location: 'Waldstadion',
      ),
      isNull,
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

    expect(find.text('Route in Google Maps'), findsOneWidget);
    expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_outward_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
