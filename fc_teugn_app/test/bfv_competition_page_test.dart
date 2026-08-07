import 'package:fc_teugn_app/features/matches/bfv_competition_page.dart';
import 'package:fc_teugn_app/features/matches/bfv_browser_page.dart';
import 'package:fc_teugn_app/features/matches/bfv_sync_tab.dart';
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
    expect(buildBfvTeamPageUri('https://evilbfv.de/team'), isNull);
    expect(buildBfvTeamPageUri(''), isNull);
  });

  test('extracts a team identifier from complete BfV widget code', () {
    const code = '''
      <script>
      BFVWidget.HTML5.zeigeMannschaftKomplett(
        "02MDU3SE2G000000VS5489B1VV4JLPLE",
        "bfv1786110689874",
        { width: "100%" }
      );
      </script>
    ''';

    expect(
      normalizedBfvWidgetTeamId(code),
      '02MDU3SE2G000000VS5489B1VV4JLPLE',
    );
    expect(isValidBfvWidgetTeamId(normalizedBfvWidgetTeamId(code)), isTrue);
  });

  test('builds only approved targets for the integrated BfV browser', () {
    final widgetUri = buildEmbeddedBfvUri(
      widgetTeamId: '02MDU3SE2G000000VS5489B1VV4JLPLE',
      teamName: 'E1-Jugend',
    );
    final teamUri = buildEmbeddedBfvUri(
      widgetTeamId: null,
      teamName: 'E1-Jugend',
      teamUrl: 'https://www.bfv.de/mannschaften/fc-teugn',
    );

    expect(widgetUri?.path, '/bfv-widget.html');
    expect(teamUri?.host, 'www.bfv.de');
    expect(
      buildEmbeddedBfvUri(
        widgetTeamId: null,
        teamName: 'E1-Jugend',
        teamUrl: 'https://example.org/not-allowed',
      ),
      isNull,
    );
  });
}
