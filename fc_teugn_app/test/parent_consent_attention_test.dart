import 'package:fc_teugn_app/core/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

ConsentTemplate template(String type, {String version = '2026-08-11'}) =>
    ConsentTemplate(
      type: type,
      version: version,
      title: type,
      shortTitle: type,
      purpose: 'Test',
      legalBasis: 'Test',
      retention: 'Test',
      options: const [],
      explicit: false,
    );

PlayerConsent consent(
  String type,
  String status, {
  String version = '2026-08-11',
}) =>
    PlayerConsent(
      id: '$type-$status',
      type: type,
      status: status,
      templateVersion: version,
    );

void main() {
  test('missing, pending and expired decisions remain open', () {
    final templates = [
      template('TEAM_PHOTO'),
      template('PHOTO'),
      template('TRANSPORT'),
    ];
    final open = openConsentTemplates(
      [
        consent('PHOTO', 'PENDING'),
        consent('TRANSPORT', 'EXPIRED'),
      ],
      templates,
    );
    expect(open.map((item) => item.type), [
      'TEAM_PHOTO',
      'PHOTO',
      'TRANSPORT',
    ]);
  });

  test('a current grant or explicit refusal completes the decision', () {
    final templates = [template('TEAM_PHOTO'), template('PHOTO')];
    final open = openConsentTemplates(
      [
        consent('TEAM_PHOTO', 'REVOKED'),
        consent('PHOTO', 'GRANTED'),
      ],
      templates,
    );
    expect(open, isEmpty);
  });

  test('a decision for an old template is requested again', () {
    final open = openConsentTemplates(
      [consent('TEAM_PHOTO', 'GRANTED', version: 'old')],
      [template('TEAM_PHOTO')],
    );
    expect(open.single.type, 'TEAM_PHOTO');
  });
}
