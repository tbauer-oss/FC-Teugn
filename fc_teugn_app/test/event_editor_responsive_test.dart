import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/features/calendar/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewport in <Size>[const Size(360, 720), const Size(1024, 800)]) {
    testWidgets(
        'event editor has no overflow at ${viewport.width.toInt()} px and large text',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = ApiClient(baseUrl: 'https://example.test');
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.contains('pitch-conflicts')
                  ? <String, dynamic>{'conflicts': <dynamic>[]}
                  : <dynamic>[],
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: EventEditorDialog(
            repository: DataRepository(client),
            teams: const [
              TeamSummary(
                id: 'team-e1',
                name: 'E1-Jugend',
                ageGroup: AgeGroupSummary(
                  id: 'age-e',
                  name: 'E-Jugend',
                  code: 'E',
                ),
                seasonName: '2026/27',
              ),
            ],
            initialTeamId: 'team-e1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Training').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mannschaftsbesprechung').last);
      await tester.pumpAndSettle();

      expect(find.text('Mannschaftsbesprechung'), findsWidgets);
      expect(find.text('Termin anlegen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
