import 'dart:ui' as ui;

import 'package:fc_teugn_app/app.dart';
import 'package:fc_teugn_app/core/app_identity.dart';
import 'package:fc_teugn_app/core/club_logo.dart';
import 'package:fc_teugn_app/core/loading/loading_widgets.dart';
import 'package:fc_teugn_app/features/launch/animated_launch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FC-Teugn-Startsequenz bleibt auf einem Handy überlauffrei',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: AnimatedLaunchScreen()),
    );

    expect(
      find.byKey(const ValueKey('fc-teugn-talents-splash-image')),
      findsOneWidget,
    );
    expect(find.text('Dein Team. Dein Verein. Deine App.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduzierte Animationen werden respektiert', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AnimatedLaunchScreen(),
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'APK-Start fällt barrierefrei direkt auf den neuen Startscreen zurück',
      (tester) async {
    var completions = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AnimatedLaunchScreen(
            playMobileIntroVideo: true,
            onIntroCompleted: () => completions++,
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('fc-teugn-talents-splash-image')),
    );
    expect(
      (image.image as AssetImage).assetName,
      AppIdentity.mobileApkSplashAsset,
    );
    expect(image.fit, BoxFit.contain);
    expect(find.byKey(const ValueKey('mobile-launch-still-layer')),
        findsOneWidget);
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  test('APK-Startvideo und hochauflösender Startscreen sind paketiert',
      () async {
    final video = await rootBundle.load(AppIdentity.mobileIntroVideoAsset);
    final image = await rootBundle.load(AppIdentity.mobileApkSplashAsset);
    final codec = await ui.instantiateImageCodec(
      image.buffer.asUint8List(
        image.offsetInBytes,
        image.lengthInBytes,
      ),
    );
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);

    expect(video.lengthInBytes, greaterThan(5 * 1024 * 1024));
    expect(image.lengthInBytes, greaterThan(1024 * 1024));
    expect(frame.image.width, greaterThanOrEqualTo(800));
    expect(frame.image.height, greaterThanOrEqualTo(1600));
    expect(frame.image.height, greaterThan(frame.image.width));
  });

  testWidgets('APK-Startscreen bleibt auch bei 320 px vollständig sichtbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AnimatedLaunchScreen(playMobileIntroVideo: true),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('fc-teugn-talents-splash-image')),
    );
    expect(image.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Web-Start zeigt das eigene Querformatmotiv mit Ladebalken',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: AnimatedLaunchScreen()),
    );

    expect(find.byKey(const ValueKey('desktop-launch-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-launch-stage')), findsNothing);
    expect(find.text('App wird vorbereitet …'), findsOneWidget);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
    );
    expect(image.fit, BoxFit.contain);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Startsequenz zeigt kein zusätzliches globales Lade-Logo',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        builder: buildLaunchScreenContent,
        home: AnimatedLaunchScreen(),
      ),
    );

    expect(find.byType(AppLoadingHost), findsNothing);
    expect(find.byType(ClubLogo), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Startsequenz wartet sichtbar auf vorgeladene Vereinsdaten',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedLaunchScreen(
          duration: Duration(milliseconds: 10),
          waitingForData: true,
          statusMessage: 'Vereinsdaten werden geladen...',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.text('Vereinsdaten werden geladen...'),
      findsOneWidget,
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Startsequenz bietet Wiederverbindung und Anmeldung an',
      (tester) async {
    var retries = 0;
    var continueToLoginCalls = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedLaunchScreen(
          errorMessage: 'Platzbelegung konnte nicht geladen werden.',
          onRetry: () => retries++,
          onContinueToLogin: () => continueToLoginCalls++,
        ),
      ),
    );

    expect(
      find.text('Platzbelegung konnte nicht geladen werden.'),
      findsOneWidget,
    );
    expect(find.text('Erneut verbinden'), findsOneWidget);
    expect(find.text('Zur Anmeldung'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Erneut verbinden'));
    expect(retries, 1);

    await tester.tap(find.text('Zur Anmeldung'));
    expect(continueToLoginCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
