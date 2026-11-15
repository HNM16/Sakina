import 'package:flutter/material.dart';

import '../../theme.dart';
import 'theme_option.dart';

/// Рӯз — day.
///
/// A complete second design rather than an inversion of the first: the accent
/// darkens to hold its contrast on a pale ground, and the bubbles become a
/// wash rather than a block. It was written a long time ago and shipped
/// unreachable — `themeMode` was pinned to dark, so no user could ever select
/// it and nobody had ever seen it render.
class DayTheme extends SakinaThemeOption {
  const DayTheme();

  @override
  String get id => 'day';

  @override
  String get labelKey => 'theme_day';

  @override
  Brightness get brightness => Brightness.light;

  @override
  ThemeData build() => SakinaTheme.build(
        brightness: Brightness.light,
        accent: SakinaColors.tileDay,
        ground: SakinaColors.dayGround,
        surface: SakinaColors.daySurface,
        text: SakinaColors.dayText,
        palette: SakinaPalette.day,
      );
}
