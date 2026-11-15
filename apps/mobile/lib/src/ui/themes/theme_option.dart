import 'package:flutter/material.dart';

/// One theme the user can choose.
///
/// A declaration, not a widget — it says what it is called, whether it is a
/// light or a dark thing, and how to build itself. Everything else about the
/// app's appearance (type, motion, component shapes, the [SakinaPalette]
/// contract) is assembled by `SakinaTheme.build`, identically for every theme.
///
/// That split is the point. A theme decides colours. It cannot decide anything
/// else, so adding the fifth one cannot quietly restyle the app for the four
/// that already worked.
///
/// ## Adding a theme
///
/// A file in this directory, a class here, and a line in `themes.dart`.
/// Nothing counts or names them anywhere else — not the picker, not the
/// settings screen, not `main.dart`.
@immutable
abstract class SakinaThemeOption {
  const SakinaThemeOption();

  /// Stable identifier, written to disk when the user picks it.
  ///
  /// Never change one once shipped: a rename silently drops every user who had
  /// chosen it back to following the phone, which looks like the app forgetting
  /// a setting.
  String get id;

  /// Key into `L10n`. Translated at build time, so the picker follows the
  /// language without the theme knowing anything about languages.
  String get labelKey;

  /// Whether this is a light or a dark thing.
  ///
  /// Used for two jobs: telling the system which of a pair to serve when the
  /// user has chosen "follow the phone", and grouping the picker so a list of
  /// a dozen themes stays readable.
  Brightness get brightness;

  ThemeData build();
}
