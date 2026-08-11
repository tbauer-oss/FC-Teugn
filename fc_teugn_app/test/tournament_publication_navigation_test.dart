import 'package:fc_teugn_app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tournament publication push keeps the planning destination for staff',
      () {
    expect(
      normalizePushActionRoute(
        '/matches/tournament-1?planning=tournament',
        isTrainer: true,
      ),
      '/trainer/matches/tournament-1?planning=tournament',
    );
  });

  test('tournament publication push keeps the planning destination for family',
      () {
    expect(
      normalizePushActionRoute(
        '/matches/tournament-1?planning=tournament',
        isTrainer: false,
      ),
      '/parent/matches/tournament-1?planning=tournament',
    );
  });
}
