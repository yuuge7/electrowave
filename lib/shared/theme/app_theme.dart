import 'package:flutter/material.dart';

import '../../features/settings/services/settings_persistence.dart';

/// The handful of colours the app paints with, resolved per brightness.
///
/// The views used to hard-code the dark palette; going through a theme
/// extension is what lets Appearance switch between light, dark and the
/// system setting without every widget growing an `if (isDark)`.
@immutable
class ElectrowaveColors extends ThemeExtension<ElectrowaveColors> {
  const ElectrowaveColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
  });

  final Color background;

  /// Cards, panels, the player bar.
  final Color surface;

  /// Menus and hover fills — one step further from the background.
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;
  final Color accent;

  /// Text/icons drawn on top of [accent].
  final Color onAccent;

  static const dark = ElectrowaveColors(
    background: Color(0xFF121212),
    surface: Color(0xFF181818),
    surfaceAlt: Color(0xFF282828),
    border: Colors.white10,
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textFaint: Colors.grey,
    accent: Colors.greenAccent,
    onAccent: Colors.black,
  );

  /// Same layout, inverted stack. The accent is a deeper green than the dark
  /// theme's: `greenAccent` on white is barely legible.
  static const light = ElectrowaveColors(
    background: Color(0xFFF4F4F6),
    surface: Colors.white,
    surfaceAlt: Color(0xFFE7E7EB),
    border: Colors.black12,
    textPrimary: Color(0xFF101014),
    textSecondary: Color(0xFF44464F),
    textFaint: Color(0xFF77797F),
    accent: Color(0xFF00A152),
    onAccent: Colors.white,
  );

  @override
  ElectrowaveColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? accent,
    Color? onAccent,
  }) {
    return ElectrowaveColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  ElectrowaveColors lerp(ThemeExtension<ElectrowaveColors>? other, double t) {
    if (other is! ElectrowaveColors) return this;
    return ElectrowaveColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension ElectrowaveTheme on BuildContext {
  /// Shorthand for the palette: `context.colors.surface`.
  ElectrowaveColors get colors =>
      Theme.of(this).extension<ElectrowaveColors>() ?? ElectrowaveColors.dark;
}

ThemeData buildAppTheme(Brightness brightness) {
  final palette =
      brightness == Brightness.dark ? ElectrowaveColors.dark : ElectrowaveColors.light;

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    primaryColor: palette.accent,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    ),
    dialogTheme: DialogThemeData(backgroundColor: palette.surface),
    popupMenuTheme: PopupMenuThemeData(color: palette.surfaceAlt),
    dividerColor: palette.border,
    extensions: [palette],
  );
}

ThemeMode toFlutterThemeMode(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
