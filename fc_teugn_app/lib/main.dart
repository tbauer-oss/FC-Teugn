import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/app_identity.dart';
import 'core/club_logo.dart';
import 'core/app_theme.dart';
import 'core/push/native_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final playMobileIntroVideo =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // Push registration must never delay the first visible frame. The service
  // owns its action stream already, so initialization can safely finish while
  // the native intro or the lightweight web launch screen is shown.
  unawaited(nativePushService.initialize().catchError((_) {}));
  // On web, only the responsive launch image that is actually rendered should
  // be downloaded. Previously three large splash images were decoded before
  // runApp, even though two of them could never be visible.
  final launchAsset = kIsWeb
      ? null
      : playMobileIntroVideo
          ? AppIdentity.mobileApkSplashAsset
          : AppIdentity.splashAsset;
  unawaited(
    preloadBrandingAssets(launchAsset: launchAsset).catchError((_) {}),
  );
  ErrorWidget.builder = (details) => Builder(
        builder: (context) => ColoredBox(
          color: context.appColors.surfaceMuted,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.appColors.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_problem_rounded,
                    color: context.appWarning,
                    size: 32,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Dieser Bereich konnte nicht dargestellt werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Bitte öffne den Bereich erneut oder ziehe zum Aktualisieren nach unten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  runApp(
    ProviderScope(
      child: FCTeugnApp(playMobileIntroVideo: playMobileIntroVideo),
    ),
  );
}
