import 'package:flutter/material.dart';

import '../../theme.dart';
import 'theme_option.dart';

/// Шаб — night.
///
/// The app's original and still its default: cheaper on an OLED battery,
/// readable in mountain sun, and the ground the palette was designed against.
class NightTheme extends SakinaThemeOption {
  const NightTheme();

  @override
  String get id => 'night';

  @override
  String get labelKey => 'theme_night';

  @override
  Brightness get brightness => Brightness.dark;

  @override
  ThemeData build() => SakinaTheme.build(
        brightness: Brightness.dark,
        accent: SakinaColors.tileNight,
        ground: SakinaColors.nightGround,
        surface: SakinaColors.nightSurface,
        text: SakinaColors.nightText,
        palette: SakinaPalette.night,
      );
}
