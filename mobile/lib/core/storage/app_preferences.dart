import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int minRadiusKm = 1;
const int maxRadiusKm = 50;
const int defaultRadiusKm = 10;
const String defaultCity = 'Vilnius';

/// Cities offered in settings until the server provides the list.
const List<String> availableCities = ['Vilnius', 'Kaunas', 'Klaipėda'];

/// Typed access to values persisted on the device with shared_preferences.
/// Invalid or missing stored values fall back to defaults.
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _themeKey = 'theme_mode';
  static const _cityKey = 'city';
  static const _radiusKey = 'search_radius_km';
  static const _ageKey = 'age_confirmed';
  static const _cachePrefix = 'cache_';

  ThemeMode get themeMode => switch (_prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeKey, mode.name);

  String get city {
    final stored = _prefs.getString(_cityKey);
    return stored != null && availableCities.contains(stored)
        ? stored
        : defaultCity;
  }

  Future<void> setCity(String city) => _prefs.setString(_cityKey, city);

  int get radiusKm {
    final stored = _prefs.getInt(_radiusKey);
    if (stored == null) {
      return defaultRadiusKm;
    }
    return stored.clamp(minRadiusKm, maxRadiusKm);
  }

  Future<void> setRadiusKm(int km) =>
      _prefs.setInt(_radiusKey, km.clamp(minRadiusKm, maxRadiusKm));

  /// Cached server data (JSON text) kept for offline use; see the stores' price cache.
  String? getCachedJson(String key) => _prefs.getString('$_cachePrefix$key');

  Future<void> setCachedJson(String key, String json) =>
      _prefs.setString('$_cachePrefix$key', json);

  Future<void> removeCachedJson(String key) => _prefs.remove('$_cachePrefix$key');

  bool get ageConfirmed => _prefs.getBool(_ageKey) ?? false;

  Future<void> setAgeConfirmed(bool value) => _prefs.setBool(_ageKey, value);
}

/// Must be overridden in `main` (and in tests) once [SharedPreferences] is loaded.
final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => throw UnimplementedError('appPreferencesProvider not overridden'),
);
