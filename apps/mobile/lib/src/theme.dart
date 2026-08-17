import 'package:flutter/material.dart';

/// Sakina's visual identity, in one place.
///
/// The name means stillness (сукунат / سكينة), and the whole system follows from
/// taking that literally. Every messenger in this market is loud; ours is
/// differentiated by being honest to its own name. See docs/BRAND.md for the
/// reasoning, including what was deliberately rejected.
///
/// Three constraints shaped every value below, and they mostly agree with each
/// other:
///
///  - **A cheap Android in bright sun.** Dark by default costs less battery and
///    stays readable outdoors. Soft contrast and few strokes cost less to paint.
///  - **Telegram's layout, our temperature.** Familiarity is free adoption, so
///    the arrangement is conventional. What changes is the colour temperature:
///    one accent instead of five, and space where other apps put dividers.
///  - **Tajik decides the sizing.** Tajik strings run roughly a third longer
///    than their English equivalents, so nothing is measured against English.
abstract final class SakinaColors {
  // Шаб — night. The ground, and the reason the system is dark-first: the sky
  // over the Pamirs, and the cheapest thing a screen can display.
  static const nightGround = Color(0xFF0A1220);
  static const nightSurface = Color(0xFF111B2C);
  static const nightRaised = Color(0xFF18243A);
  static const nightLine = Color(0xFF22314B);
  static const nightText = Color(0xFFE7EDF7);
  static const nightMuted = Color(0xFF8496B3);

  // Рӯз — day. A complete second design, not an inversion of the first.
  static const dayGround = Color(0xFFF4F7FB);
  static const daySurface = Color(0xFFFFFFFF);
  static const dayLine = Color(0xFFDFE7F1);
  static const dayText = Color(0xFF0C1524);
  static const dayMuted = Color(0xFF5A6C88);

  /// Фирӯза — the glaze on Samanid tilework, and the only accent.
  ///
  /// Chosen over the obvious candidates on purpose: Telegram owns bright blue,
  /// WhatsApp owns green (which also rules out the instinctive "Islamic
  /// green"), and the flag palette belongs to the state messenger that launched
  /// here in 2025. Firuza is ours in a way a flag colour is not.
  static const tileNight = Color(0xFF35B9AC);
  static const tileDay = Color(0xFF12867C);

  /// Заъфарон — saffron. Rare warmth only: a Navruz greeting, a pinned chat.
  /// A screen with three accent colours has none.
  static const saffronNight = Color(0xFFE3AC55);
  static const saffronDay = Color(0xFFB07A1E);

  /// Анор — pomegranate. Appears only when something is lost or destroyed.
  static const anorNight = Color(0xFFD25A54);
  static const anorDay = Color(0xFFB23B36);

  // Own messages sit in a deep tile wash; theirs on the raised surface.
  static const bubbleMineNight = Color(0xFF14504A);
  static const bubbleTheirsNight = nightRaised;
  static const bubbleMineDay = Color(0xFFD2EEE9);
  static const bubbleTheirsDay = Color(0xFFFFFFFF);
}

/// Extra roles Material's [ColorScheme] has no slot for.
///
/// Reading bubble colours off `primaryContainer` would work until someone
/// changed the seed and quietly restyled the conversation, so they are named
/// explicitly instead.
@immutable
class SakinaPalette extends ThemeExtension<SakinaPalette> {
  const SakinaPalette({
    required this.bubbleMine,
    required this.bubbleTheirs,
    required this.muted,
    required this.saffron,
    required this.anor,
    required this.line,
  });

  final Color bubbleMine;
  final Color bubbleTheirs;
  final Color muted;
  final Color saffron;
  final Color anor;
  final Color line;

  static const night = SakinaPalette(
    bubbleMine: SakinaColors.bubbleMineNight,
    bubbleTheirs: SakinaColors.bubbleTheirsNight,
    muted: SakinaColors.nightMuted,
    saffron: SakinaColors.saffronNight,
    anor: SakinaColors.anorNight,
    line: SakinaColors.nightLine,
  );

  static const day = SakinaPalette(
    bubbleMine: SakinaColors.bubbleMineDay,
    bubbleTheirs: SakinaColors.bubbleTheirsDay,
    muted: SakinaColors.dayMuted,
    saffron: SakinaColors.saffronDay,
    anor: SakinaColors.anorDay,
    line: SakinaColors.dayLine,
  );

  static SakinaPalette of(BuildContext context) =>
      Theme.of(context).extension<SakinaPalette>() ?? night;

  @override
  SakinaPalette copyWith({
    Color? bubbleMine,
    Color? bubbleTheirs,
    Color? muted,
    Color? saffron,
    Color? anor,
    Color? line,
  }) {
    return SakinaPalette(
      bubbleMine: bubbleMine ?? this.bubbleMine,
      bubbleTheirs: bubbleTheirs ?? this.bubbleTheirs,
      muted: muted ?? this.muted,
      saffron: saffron ?? this.saffron,
      anor: anor ?? this.anor,
      line: line ?? this.line,
    );
  }

  @override
  SakinaPalette lerp(SakinaPalette? other, double t) {
    if (other == null) return this;
    return SakinaPalette(
      bubbleMine: Color.lerp(bubbleMine, other.bubbleMine, t)!,
      bubbleTheirs: Color.lerp(bubbleTheirs, other.bubbleTheirs, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      saffron: Color.lerp(saffron, other.saffron, t)!,
      anor: Color.lerp(anor, other.anor, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

abstract final class SakinaTheme {
  /// Noto Sans, because coverage is its entire reason for existing.
  ///
  /// Tajik Cyrillic needs ғ ӣ қ ӯ ҳ ҷ. A face without them falls back mid-word,
  /// which is the fastest possible way for the app to look foreign. Noto ships
  /// with Android, so there is nothing to download on a metered connection.
  static const fontFamily = 'Noto Sans';
  static const fontFallback = <String>['Roboto'];

  /// Short and soft. Motion should settle, never bounce — no springs, no
  /// overshoot. It reads as calm, and it costs a budget phone nothing, so the
  /// aesthetic and the constraint agree for once.
  ///
  /// This governs motion we author. Route transitions keep the platform
  /// builder's own timing, because a navigation that runs faster than every
  /// other app on the phone reads as broken rather than brisk.
  static const motionDuration = Duration(milliseconds: 180);
  static const motionCurve = Curves.easeOutCubic;

  static final _typography = Typography.material2021(platform: TargetPlatform.android);

  static ThemeData night() => _build(
        brightness: Brightness.dark,
        accent: SakinaColors.tileNight,
        ground: SakinaColors.nightGround,
        surface: SakinaColors.nightSurface,
        text: SakinaColors.nightText,
        palette: SakinaPalette.night,
      );

  static ThemeData day() => _build(
        brightness: Brightness.light,
        accent: SakinaColors.tileDay,
        ground: SakinaColors.dayGround,
        surface: SakinaColors.daySurface,
        text: SakinaColors.dayText,
        palette: SakinaPalette.day,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color ground,
    required Color surface,
    required Color text,
    required SakinaPalette palette,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      surface: ground,
      onSurface: text,
      error: palette.anor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      extensions: [palette],

      // Space instead of lines: fewer strokes is less to render and less to
      // look at. Dividers are opt-in, not the default.
      dividerTheme: DividerThemeData(
        color: palette.line,
        thickness: 1,
        space: 1,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: palette.line)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),

      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: palette.muted,
        // Roomier than Material's default, because Tajik names and previews run
        // long and cramping them is how a UI starts feeling translated.
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? SakinaColors.nightSurface : ground,
        hintStyle: TextStyle(color: palette.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: brightness == Brightness.dark
              ? SakinaColors.nightGround
              : Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: SakinaColors.nightRaised,
        contentTextStyle: const TextStyle(color: SakinaColors.nightText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // Sentence case everywhere — Tajik and Russian both read badly in ALL
      // CAPS, and shouting is off-brief.
      //
      // `.apply` repaints every style from our own tokens, so the black/white
      // pick below only decides what we start from. It is still chosen by
      // brightness rather than hardcoded, so the base never disagrees with the
      // theme it belongs to.
      textTheme: (brightness == Brightness.dark
              ? _typography.white
              : _typography.black)
          .apply(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            bodyColor: text,
            displayColor: text,
          ),

      // Fade-and-settle on Android, the native slide on iOS. Neither springs.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// The mark: a chorkhona, the stepped skylight of a Pamiri house.
///
/// Four squares, each turned against the one below, opening to let light into
/// the home — the right shape for an app whose main job is keeping families in
/// touch across a border. It is also four straight-edged shapes, so it costs
/// almost nothing to paint and stays legible at 16 pixels, which a paper plane
/// does not.
class ChorkhonaMark extends StatelessWidget {
  const ChorkhonaMark({super.key, this.size = 40, this.color, this.coreColor});

  final double size;
  final Color? color;
  final Color? coreColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SakinaPalette.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _ChorkhonaPainter(
        stroke: color ?? theme.colorScheme.primary,
        core: coreColor ?? palette.saffron,
      ),
    );
  }
}

/// 45° in radians, spelled out so the painter needs no `dart:math` import.
const _fortyFiveDegrees = 0.7853981633974483; // pi / 4

class _ChorkhonaPainter extends CustomPainter {
  _ChorkhonaPainter({required this.stroke, required this.core});

  final Color stroke;
  final Color core;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final unit = size.width / 100;

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * unit
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;

    void square(double half, double turns) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(turns);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: half * 2 * unit,
            height: half * 2 * unit,
          ),
          Radius.circular(3 * unit),
        ),
        outline,
      );
      canvas.restore();
    }

    // Each tier turned 45° against the one below — that alternation is what
    // makes the silhouette an eight-pointed opening rather than a plain square.
    //
    // It sheds tiers rather than collapsing. Three nested outlines inside 24
    // logical pixels merge into a blob, so small sizes keep the outer square,
    // the one 45° turn that makes the shape recognisable, and the core. This is
    // what lets the mark sit in an app bar and on a splash screen unchanged.
    square(38, 0);
    if (size.width >= 24) square(26, _fortyFiveDegrees);
    if (size.width >= 40) square(17, 0);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(_fortyFiveDegrees);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 16 * unit, height: 16 * unit),
        Radius.circular(2 * unit),
      ),
      Paint()..color = core,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChorkhonaPainter old) =>
      old.stroke != stroke || old.core != core;
}
