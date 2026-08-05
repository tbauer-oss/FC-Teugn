import 'package:fc_teugn_app/core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sorgeberechtigten-Beziehungen werden einheitlich deutsch angezeigt',
      () {
    expect(guardianRelationshipLabel('MOTHER'), 'Mutter');
    expect(guardianRelationshipLabel('FATHER'), 'Vater');
    expect(guardianRelationshipLabel('GUARDIAN'), 'Sorgeberechtigt');
    expect(guardianRelationshipLabel('OTHER'), 'Sorgeberechtigt');
  });
}
