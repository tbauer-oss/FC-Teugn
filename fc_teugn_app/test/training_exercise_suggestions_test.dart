import 'package:fc_teugn_app/core/models/training.dart';
import 'package:fc_teugn_app/features/training/training_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exercise library provides age-appropriate E-youth ideas', () {
    final training = TrainingModel(
      id: 'training-1',
      title: 'Training',
      startAt: DateTime(2026, 8, 18, 17, 15),
      location: 'Platz 1',
      teamId: 'team-e1',
      teamNames: ['E1-Jugend'],
      attendance: [],
      roster: [],
    );

    final suggestions = trainingExerciseSuggestions(training);

    expect(suggestions, hasLength(greaterThanOrEqualTo(4)));
    expect(suggestions.map((item) => item.category),
        everyElement(contains('E-Jugend')));
    expect(suggestions.map((item) => item.title), contains('Finten-Inseln'));
    expect(suggestions.every((item) => item.id.startsWith('preset:')), isTrue);
  });
}
