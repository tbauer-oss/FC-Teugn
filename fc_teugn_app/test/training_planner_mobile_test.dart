import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/training.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/training/training_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrainingRepository extends DataRepository {
  _TrainingRepository() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<TrainingModel> training(String trainingId) async => TrainingModel(
        id: trainingId,
        title: 'Training',
        startAt: DateTime(2026, 8, 18, 17, 15),
        location: 'Platz 1 unten',
        teamId: 'team-e1',
        teamNames: const ['E1-Jugend'],
        attendance: const [],
        roster: const [],
      );

  @override
  Future<List<TrainingCoachModel>> trainingCoaches(String trainingId) async =>
      const [
        TrainingCoachModel(
          id: 'coach-1',
          name: 'Tobias Trainer',
          role: 'TRAINER',
        ),
      ];

  @override
  Future<List<TrainingExerciseModel>> trainingExercises() async => const [];
}

void main() {
  testWidgets('training planner stays usable at 320 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_TrainingRepository()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: TrainingPlannerPage(trainingId: 'training-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Schwerpunkte'), findsOneWidget);
    expect(find.text('Trainer auswählen · Mehrfachauswahl'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Übungen'));
    await tester.pumpAndSettle();

    expect(find.text('Finten-Inseln'), findsOneWidget);
    expect(find.textContaining('Übungen & Jugendideen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
