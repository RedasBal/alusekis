import 'package:material_ui/material_ui.dart';

/// Minimum size of any tappable area, in logical pixels.
const double minTapTarget = 48;

const Color _seed = Color(0xFFE0A100);

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  const minSize = Size(minTapTarget, minTapTarget);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minSize),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: minSize),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: minSize),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: minSize),
    ),
    navigationBarTheme: const NavigationBarThemeData(height: 72),
  );
}

final ThemeData lightTheme = buildAppTheme(Brightness.light);
final ThemeData darkTheme = buildAppTheme(Brightness.dark);
