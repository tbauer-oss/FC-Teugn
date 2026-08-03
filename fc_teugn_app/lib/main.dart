import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/club_logo.dart';
import 'core/app_theme.dart';
import 'core/push/native_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await nativePushService.initialize();
  await preloadBrandingAssets();
  ErrorWidget.builder = (details) => ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync_problem_rounded,
                    color: AppColors.gold, size: 32),
                SizedBox(height: 10),
                Text(
                  'Dieser Bereich konnte nicht dargestellt werden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 5),
                Text(
                  'Bitte öffne den Bereich erneut oder ziehe zum Aktualisieren nach unten.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      );
  runApp(const ProviderScope(child: FCTeugnApp()));
}
