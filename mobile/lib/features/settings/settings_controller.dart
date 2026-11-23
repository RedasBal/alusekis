import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_preferences.dart';

class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.city,
    required this.radiusKm,
  });

  final ThemeMode themeMode;
  final String city;
  final int radiusKm;

  SettingsState copyWith({ThemeMode? themeMode, String? city, int? radiusKm}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        city: city ?? this.city,
        radiusKm: radiusKm ?? this.radiusKm,
      );
}

/// Theme, selected city and search radius; every change is persisted.
class SettingsController extends Notifier<SettingsState> {
  AppPreferences get _prefs => ref.read(appPreferencesProvider);

  @override
  SettingsState build() {
    final prefs = ref.watch(appPreferencesProvider);
    return SettingsState(
      themeMode: prefs.themeMode,
      city: prefs.city,
      radiusKm: prefs.radiusKm,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setThemeMode(mode);
  }

  Future<void> setCity(String city) async {
    if (!availableCities.contains(city)) {
      return;
    }
    state = state.copyWith(city: city);
    await _prefs.setCity(city);
  }

  Future<void> setRadiusKm(int km) async {
    final value = km.clamp(minRadiusKm, maxRadiusKm);
    state = state.copyWith(radiusKm: value);
    await _prefs.setRadiusKm(value);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
