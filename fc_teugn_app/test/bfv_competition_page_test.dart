import 'package:fc_teugn_app/features/matches/bfv_competition_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the official BfV widget URL for the selected team', () {
    final uri = buildBfvWidgetUri(
      teamName: 'E1-Jugend',
      widgetTeamId: '02MDU3SE2G000000VS5489B1VV4JLPLE',
    );

    expect(uri?.host, 'fcteugnapp.vercel.app');
    expect(uri?.path, '/bfv-widget.html');
    expect(
      uri?.queryParameters['teamId'],
      '02MDU3SE2G000000VS5489B1VV4JLPLE',
    );
    expect(uri?.queryParameters['teamName'], 'E1-Jugend');
  });

  test('does not create a widget URL without a team identifier', () {
    expect(
      buildBfvWidgetUri(teamName: 'E1-Jugend', widgetTeamId: '  '),
      isNull,
    );
  });

  test('accepts only official BfV team page URLs', () {
    expect(
      buildBfvTeamPageUri(
        'https://www.bfv.de/mannschaften/fc-teugn/02MDU3SE2G000000VS5489B1VV4JLPLE',
      )?.host,
      'www.bfv.de',
    );
    expect(buildBfvTeamPageUri('https://example.org/team'), isNull);
    expect(buildBfvTeamPageUri(''), isNull);
  });
}
