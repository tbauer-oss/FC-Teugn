import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/club_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preloadBrandingAssets();
  runApp(const ProviderScope(child: FCTeugnApp()));
}
