import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final configuration in const [
    (Size(320, 568), 2.0),
    (Size(360, 640), 1.8),
    (Size(412, 915), 2.0),
  ]) {
    testWidgets(
      'five destination navigation stays readable at '
      '${configuration.$1.width}px and ${configuration.$2}x text',
      (tester) async {
        final size = configuration.$1;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(configuration.$2),
              ),
              child: Scaffold(
                bottomNavigationBar: NavigationBar(
                  height: 72,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_rounded),
                      label: 'Start',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.groups_rounded),
                      label: 'Team',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_rounded),
                      label: 'Kalender',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.sports_soccer_rounded),
                      label: 'Spiele',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.apps_rounded),
                      label: 'Mehr',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final label in const [
          'Start',
          'Team',
          'Kalender',
          'Spiele',
          'Mehr'
        ]) {
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
        }
      },
    );
  }
}
