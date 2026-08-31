import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/features/matches/matchday_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final configuration in const [
    (Size(320, 568), 1.5),
    (Size(360, 640), 1.8),
    (Size(412, 915), 2.0),
  ]) {
    testWidgets(
      'match communication buttons keep all text at '
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
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MatchCommunicationActions(
                    match: _match(),
                    onPublishInternal: () {},
                    onReleaseFamily: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final label in const [
          'Spieltag intern teilen',
          'Für Familien freigeben',
        ]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          final button = find.ancestor(
            of: text,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(button, findsOneWidget);
          final textRect = tester.getRect(text);
          final buttonRect = tester.getRect(button);
          expect(textRect.left, greaterThanOrEqualTo(buttonRect.left - .5));
          expect(textRect.right, lessThanOrEqualTo(buttonRect.right + .5));
          expect(textRect.top, greaterThanOrEqualTo(buttonRect.top - .5));
          expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom + .5));
        }
      },
    );
  }
}

MatchdayModel _match() => MatchdayModel(
      id: 'button-scaling',
      title: 'FC Teugn · Gegner',
      startAt: DateTime(2026, 8, 15, 10),
      location: 'Stadion am Kreutweg, Teugn',
      teamId: 'team-1',
      canPublishInternal: true,
      canReleaseFamily: true,
    );
