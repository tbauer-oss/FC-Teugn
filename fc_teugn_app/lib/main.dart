import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/club_logo.dart';
import 'core/push/native_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await nativePushService.initialize();
  await preloadBrandingAssets();
  runApp(const ProviderScope(child: FCTeugnApp()));
}
