import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/pitch_occupancy.dart';
import 'package:fc_teugn_app/core/models/training.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/training/training_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PartiallyUnavailableRepository extends DataRepository {
  _PartiallyUnavailableRepository() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<TrainingModel>> trainings() async => <TrainingModel>[];

  @override
  Future<OrganizationContext> organizationContext() =>
      Future.error(Exception('organization unavailable'));

  @override
  Future<PitchOccupancyPlan> pitchOccupancy({bool indoor = false}) =>
      Future.error(Exception('occupancy unavailable'));
}

void main() {
  testWidgets('partial API failures do not hide available training sessions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(
            _PartiallyUnavailableRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: TrainingsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Trainingsplanung nicht erreichbar'), findsNothing);
    expect(find.text('Noch keine planbaren Trainingstermine'), findsOneWidget);
    expect(find.textContaining('Mannschaftsdaten'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Plätze'));
    await tester.pumpAndSettle();
    expect(find.text('Platzbelegung nicht erreichbar'), findsOneWidget);
    expect(find.text('Erneut laden'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Halle'));
    await tester.pumpAndSettle();
    expect(find.text('Hallenbelegung nicht erreichbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
