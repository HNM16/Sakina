import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One place that knows how wide the screen is and what that means.
///
/// The device matrix this is built against lives in
/// `tools/device-matrix/devices.json`, and `tools/device-matrix/verify.mjs`
/// fails if the numbers below drift from it. Read that file before changing a
/// constant here.
///
/// Two rules govern everything in this file:
///
///  1. **Nothing branches on a device.** There is no `isIPhone`, no model list.
///     The matrix exists to establish the *range* the layout has to survive —
///     320 to 834 logical units — and to give the verifier real widths to run
///     the rules at. A layout that needs to know it is on an iPhone 15 is a
///     layout that will break on the iPhone 18.
///
///  2. **The breakpoints are Material's, except one.** `compact` and `medium`
///     are the Material 3 window size classes, unchanged, because the widget
///     library already thinks in them and inventing a parallel set is the kind
///     of gratuitous difference `docs/UX.md` argues against. [narrowWidth] is
///     ours, and it sits *inside* compact — see below.
@immutable
class SakinaLayout {
  const SakinaLayout._({
    required this.width,
    required this.height,
    required this.safeArea,
    required this.keyboardInset,
    required this.textScale,
    required this.animationsDisabled,
  });

  // --------------------------------------------------------------------
  // Breakpoints. Every one of these is a real device edge, not a round number.
  // --------------------------------------------------------------------

  /// The Galaxy Z Fold's outer screen is 344 wide and the iPhone 11 Pro is 375.
  /// Below this line a row cannot hold an avatar, two lines of text, a
  /// timestamp and an unread badge without one of them being a lie, so the
  /// layout drops the least important thing instead of squeezing all four.
  static const double narrowWidth = 375;

  /// Material 3 compact/medium boundary. Below it, one pane.
  static const double compactWidth = 600;

  /// Material 3 medium/expanded boundary.
  static const double mediumWidth = 840;

  /// iOS Human Interface Guidelines' floor, and hard invariant 6 in the
  /// design-tells guardrails. Material asks for 48, which is what we actually
  /// ship; this is the number the verifier refuses to go below.
  static const double minTapTarget = 44;

  /// Our own controls are sized to Material's 48, not the 44 floor. The gap is
  /// deliberate slack: it means a rounding error or a font change cannot push a
  /// real control under the invariant.
  static const double tapTarget = 48;

  /// Nothing may overflow at this width. It is not a target — no one in the
  /// audience is buying a 320dp phone in 2026 — it is the floor the layout is
  /// proven against so that a narrow split-screen or a huge font cannot break
  /// it.
  static const double minSupportedWidth = 320;

  /// Beyond this a message column stops being readable and starts being a
  /// banner. Tablets get margins, not 800-unit-wide bubbles.
  static const double readableColumnWidth = 720;

  final double width;
  final double height;
  final EdgeInsets safeArea;

  /// How far the keyboard intrudes. The composer sits on top of this.
  final double keyboardInset;

  /// Already clamped — see [maxTextScale].
  final double textScale;

  /// The platform's "reduce motion" switch. Guardrail G2: motion without a path
  /// that disables it is a defect, not a preference.
  final bool animationsDisabled;

  static SakinaLayout of(BuildContext context) {
    final media = MediaQuery.of(context);
    return SakinaLayout._(
      width: media.size.width,
      height: media.size.height,
      // viewPadding rather than padding: padding goes to zero when the keyboard
      // is up, and the home indicator does not stop existing because someone is
      // typing.
      safeArea: media.viewPadding,
      keyboardInset: media.viewInsets.bottom,
      textScale: clampTextScale(media.textScaler.scale(1)),
      animationsDisabled: media.disableAnimations,
    );
  }

  /// Accessibility text sizes go to 3.1x on iOS and 2.0x on Android. Past a
  /// point the choice is between a broken layout and a smaller font, and a
  /// broken layout helps nobody — but the floor is 1.0, because shrinking text
  /// for a user who asked for bigger text is user-hostile.
  static const double maxTextScale = 1.6;

  static double clampTextScale(double raw) => raw.clamp(1.0, maxTextScale);

  WindowSize get windowSize {
    if (width >= mediumWidth) return WindowSize.expanded;
    if (width >= compactWidth) return WindowSize.medium;
    return WindowSize.compact;
  }

  /// Fold outer screen, split-screen multitasking, and the 320 floor.
  bool get isNarrow => width < narrowWidth;

  /// The chat list and the open conversation side by side.
  ///
  /// This is the whole reason the matrix includes the Fold's inner screen and
  /// the Tab S9: the app is on those devices whether or not it was designed for
  /// them, and a phone layout stretched to 800 units is how you get a chat list
  /// with 700 units of dead space next to each name.
  bool get usesTwoPane => windowSize != WindowSize.compact;

  /// Left pane in two-pane mode. Bounded at both ends: proportional alone gives
  /// a 280-unit list on a Fold and a 400-unit list on a desktop window.
  double get listPaneWidth {
    if (!usesTwoPane) return width;
    return (width * 0.36).clamp(300.0, 400.0);
  }

  double get detailPaneWidth => usesTwoPane ? width - listPaneWidth : width;

  /// Horizontal breathing room. Twelve on a Fold outer screen is not stinginess
  /// — at 344 units, 16-unit gutters cost 9% of the line.
  double get gutter => isNarrow ? 12 : 16;

  /// Vertical rhythm between grouped things. Brand rule 4 is space instead of
  /// lines, which makes this token do the work a divider would.
  double get gap => isNarrow ? 10 : 14;

  double get avatarSize => isNarrow ? 40 : 48;

  /// How wide a message bubble may get.
  ///
  /// The fraction goes *up* on narrow screens, which looks backwards until you
  /// run the numbers: 78% of a 344-unit Fold is 268 units, and a Tajik word
  /// like "Хабарнигорӣ" plus a timestamp and a tick does not fit in 268 at an
  /// accessibility text size. The cap at [readableColumnWidth] * 0.8 is what
  /// stops a tablet from rendering a two-word reply across 600 units.
  double bubbleMaxWidth(double availableWidth) {
    final fraction = isNarrow ? 0.86 : 0.78;
    return math.min(availableWidth * fraction, readableColumnWidth * 0.8);
  }

  /// The conversation column on a wide screen, centred rather than stretched.
  double get contentMaxWidth => math.min(detailPaneWidth, readableColumnWidth);

  /// Motion duration that respects the platform's reduce-motion switch.
  ///
  /// Kept because layout already knows [animationsDisabled] and a caller that
  /// has a [SakinaLayout] should not have to reach for a second module. The
  /// vocabulary — which durations exist and what they are for — lives in
  /// `motion.dart`, and that is what new code should use.
  Duration motion([Duration base = const Duration(milliseconds: 180)]) =>
      animationsDisabled ? Duration.zero : base;

  /// Whether a secondary label has room to exist at all.
  ///
  /// Used instead of scattering `if (width < 375)` through widgets. At a large
  /// text scale even a wide phone runs out of horizontal room, so this is a
  /// function of both, which a raw width check would miss.
  bool get hasRoomForInlineLabels => width / textScale >= narrowWidth;

  /// Padding for a scrollable that must clear the notch and the home indicator.
  /// The keyboard is handled separately because a list should scroll under it,
  /// not be padded away from it.
  EdgeInsets get screenPadding => EdgeInsets.only(
        left: gutter + safeArea.left,
        right: gutter + safeArea.right,
        top: gap,
        bottom: gap + safeArea.bottom,
      );

  @override
  bool operator ==(Object other) =>
      other is SakinaLayout &&
      other.width == width &&
      other.height == height &&
      other.safeArea == safeArea &&
      other.keyboardInset == keyboardInset &&
      other.textScale == textScale &&
      other.animationsDisabled == animationsDisabled;

  @override
  int get hashCode =>
      Object.hash(width, height, safeArea, keyboardInset, textScale, animationsDisabled);
}

/// Material 3's window size classes. Named rather than inferred at each call
/// site so that "is this a tablet" is asked once, in one vocabulary.
enum WindowSize { compact, medium, expanded }
