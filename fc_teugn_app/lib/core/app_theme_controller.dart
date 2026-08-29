import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppThemePreference { system, light, dark }

extension AppThemePreferenceUi on AppThemePreference {
  ThemeMode get themeMode => switch (this) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };

  String get label => switch (this) {
        AppThemePreference.system => 'System',
        AppThemePreference.light => 'Hell',
        AppThemePreference.dark => 'Dunkel',
      };
}

class AppThemeController extends StateNotifier<AppThemePreference> {
  AppThemeController({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(AppThemePreference.system) {
    unawaited(_restore());
  }

  static const _storageKey = 'fc_teugn_theme_preference_v1';
  final FlutterSecureStorage _storage;

  Future<void> _restore() async {
    try {
      final stored = await _storage.read(key: _storageKey);
      for (final preference in AppThemePreference.values) {
        if (preference.name == stored) {
          state = preference;
          return;
        }
      }
    } catch (_) {
      // Bei nicht verfügbarem Schlüsselspeicher bleibt die Systemdarstellung.
    }
  }

  Future<void> select(AppThemePreference preference) async {
    state = preference;
    try {
      await _storage.write(key: _storageKey, value: preference.name);
    } catch (_) {
      // Die Auswahl gilt für die laufende Sitzung weiterhin sofort.
    }
  }
}

final appThemePreferenceProvider =
    StateNotifierProvider<AppThemeController, AppThemePreference>(
        (ref) => AppThemeController());
