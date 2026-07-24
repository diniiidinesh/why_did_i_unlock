import 'package:flutter/material.dart';

/// Beacon brand tokens — warm amber "guiding light" on dark UI.
/// Replaces the old Material purple (`#6200EE`) accent.
abstract final class BeaconColors {
  /// Primary accent — toggles, FAB, chart "Done", borders, highlights.
  static const Color amber = Color(0xFFFFB300);

  /// Soft amber for glows / shadows (≈40% opacity).
  static const Color amberGlow = Color(0x66FFB300);

  /// Frosted overlay fill — black @ 60% (bubble / glass shells).
  static const Color glassFill = Color(0x99000000);

  /// Pure white content on glass (max contrast per Beacon directive).
  static const Color onGlass = Color(0xFFFFFFFF);

  /// Dark ink on amber/cream filled controls (e.g. Done check).
  static const Color onAmber = Color(0xFF1A1200);
}

/// Dark [ThemeData] seeded with [BeaconColors.amber] so Material controls
/// (Switch, FAB, progress, buttons) pick up Beacon without per-widget hacks.
ThemeData beaconDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BeaconColors.amber,
    brightness: Brightness.dark,
    primary: BeaconColors.amber,
    onPrimary: BeaconColors.onAmber,
    secondary: BeaconColors.amber,
    onSecondary: BeaconColors.onAmber,
    surface: Colors.black,
    onSurface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BeaconColors.amber,
      foregroundColor: BeaconColors.onAmber,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BeaconColors.onAmber;
        return Colors.white70;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BeaconColors.amber;
        return Colors.white24;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BeaconColors.amber;
        return Colors.white38;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BeaconColors.amber,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BeaconColors.amber,
        foregroundColor: BeaconColors.onAmber,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: BeaconColors.amber),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Colors.white70),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BeaconColors.amber;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(BeaconColors.onAmber),
      side: const BorderSide(color: Colors.white54),
    ),
  );
}
