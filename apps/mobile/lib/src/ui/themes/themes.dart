import 'package:flutter/material.dart';

import 'day_theme.dart';
import 'night_theme.dart';
import 'theme_option.dart';

/// Every theme the app ships, in the order the picker shows them.
///
/// The only place that knows how many there are. Adding one is a file in this
/// directory and a line in this list.
const sakinaThemes = <SakinaThemeOption>[
  NightTheme(),
  DayTheme(),
];

/// Resolution, kept here so `main.dart` never reasons about themes.
abstract final class SakinaThemes {
  /// What "follow the phone" serves when the system asks for dark.
  static SakinaThemeOption get systemDark =>
      sakinaThemes.firstWhere((t) => t.brightness == Brightness.dark);

  /// And for light.
  static SakinaThemeOption get systemLight =>
      sakinaThemes.firstWhere((t) => t.brightness == Brightness.light);

  /// The stored choice, or null for "follow the phone".
  ///
  /// An id that no longer exists resolves to null rather than throwing: a theme
  /// withdrawn in an update must degrade to following the phone, not crash the
  /// app on launch for everyone who had chosen it.
  static SakinaThemeOption? byId(String? id) {
    if (id == null) return null;
    for (final theme in sakinaThemes) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}
