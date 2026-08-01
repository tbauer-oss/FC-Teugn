import 'package:fc_teugn_app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification message links open the role-correct inbox', () {
    expect(
      normalizePushActionRoute(
        '/messages/announcement-1',
        isTrainer: true,
      ),
      '/trainer/messages',
    );
    expect(
      normalizePushActionRoute(
        '/messages/announcement-1',
        isTrainer: false,
      ),
      '/parent/messages',
    );
  });

  test('unknown relative push links return to the role landing page', () {
    expect(
      normalizePushActionRoute('not-a-route', isTrainer: true),
      '/trainer',
    );
    expect(
      normalizePushActionRoute('not-a-route', isTrainer: false),
      '/parent',
    );
  });
}
