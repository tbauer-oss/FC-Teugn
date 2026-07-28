import 'package:fc_teugn_app/core/models/team_operations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equipment availability subtracts all active assignments', () {
    final item = EquipmentItemModel.fromJson({
      'id': 'equipment-1',
      'name': 'Trainingsbälle',
      'category': 'BALL',
      'quantity': 12,
      'status': 'ACTIVE',
      'assignments': [
        {
          'id': 'assignment-1',
          'quantity': 3,
          'assignedAt': '2026-07-28T18:00:00.000Z',
          'assignedToUser': {'id': 'user-1', 'name': 'Trainer Beispiel'},
        },
        {
          'id': 'assignment-2',
          'quantity': 2,
          'assignedAt': '2026-07-28T18:00:00.000Z',
          'assignedToPlayer': {
            'id': 'player-1',
            'firstName': 'Max',
            'lastName': 'Muster',
          },
        },
      ],
    });

    expect(item.assignedQuantity, 5);
    expect(item.availableQuantity, 7);
    expect(item.assignments.last.recipient.name, 'Max Muster');
  });

  test('checklist progress is derived from persisted items', () {
    final run = ChecklistRunModel.fromJson({
      'id': 'run-1',
      'title': 'Spieltagscheckliste',
      'category': 'SPIELTAG',
      'status': 'ACTIVE',
      'items': [
        {
          'id': 'item-1',
          'title': 'Trikots',
          'isRequired': true,
          'isCompleted': true,
        },
        {
          'id': 'item-2',
          'title': 'Bälle',
          'isRequired': true,
          'isCompleted': false,
        },
      ],
    });

    expect(run.completedCount, 1);
    expect(run.progress, .5);
  });
}
