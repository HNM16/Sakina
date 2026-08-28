import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Every animation and every vibration in the app, in one place.
///
/// Two reasons this is a module rather than a handful of constants scattered
/// through widgets:
///
///  1. **Guardrail G2.** Motion needs a path that *removes* it, not one that
///     shortens it. Routing everything through [SakinaMotion] means the
///     reduce-motion branch is written once and cannot be forgotten in the
///     thirteenth widget. `tools/motion-check.mjs` fails the build if an
///     animation API is used with a raw `Duration` instead.
///
///  2. **Haptics are the cheapest way to feel expensive and the easiest thing
///     to overdo.** A phone that buzzes on every scroll tick is a phone someone
///     turns the haptics off on, and then the feedback that mattered is gone
///     too. Writing the vocabulary down is what stops it drifting.
///
/// The durations come from `docs/BRAND.md` rule 3: motion settles, never
/// bounces. No springs with overshoot, nothing over 300ms, and the default is
/// 180ms because that is fast enough to feel immediate and slow enough to be
/// followed by the eye.
abstract final class SakinaMotion {
  // --------------------------------------------------------------------
  // Durations. Named for what they are *for*, not for how long they are —
  // "quick" survives a change of mind about milliseconds; "ms120" does not.
  // --------------------------------------------------------------------

  /// A state flip: a tick appearing, a badge changing, a colour settling.
  static const quick = Duration(milliseconds: 120);

  /// The default. A sheet, a fade, a list row arriving.
  static const base = Duration(milliseconds: 180);

  /// Something crossing the screen: a hero, a bubble leaving the composer.
  static const travel = Duration(milliseconds: 260);

  /// The longest thing we do. A full-screen transition on a slow device.
  static const long = Duration(milliseconds: 320);

  // Loop periods. A repeating indicator's duration is one cycle, not a
  // transition — but it is still motion, and the check in tools/motion-check.mjs
  // is right to insist it be named here rather than written at the call site.

  /// A skeleton breathing while content loads.
  static const pulse = Duration(milliseconds: 900);

  /// One trip of the highlight across the typing dots.
  static const typing = Duration(milliseconds: 1100);

  // ------------------------------------------------------------------
  // The three primitives. See docs/MOTION.md for why these and not others.
  // ------------------------------------------------------------------

  /// ТОБ — one crossing of the light pass.
  ///
  /// Fires when something becomes *true*, once, and never loops. That is the
  /// whole distinction between this and a loading shimmer, which means the
  /// opposite: a shimmer says "waiting", this says "done".
  static const tob = Duration(milliseconds: 320);

  /// The band's share of the surface it crosses.
  static const double tobBand = 0.28;

  /// НАФАС — the breath, for whatever is being waited on.
  ///
  /// The object in doubt expresses its own state, so there is never a separate
  /// spinner next to the thing you actually care about.
  static const nafas = Duration(milliseconds: 900);
  static const double nafasFloor = 0.55;

  /// ЧАРХ — one step of the turning mark, turn plus hold.
  ///
  /// Eight positions to a revolution. The chorkhona has four-fold symmetry, so
  /// a smooth spin would look almost static; stepping makes it visibly turn and
  /// alternates the silhouette between square and diamond.
  static const charkhStep = Duration(milliseconds: 230);
  static const int charkhPositions = 8;

  /// How much of a step is spent turning rather than held.
  static const double charkhTurnFraction = 110 / 230;

  /// How long a staggered list takes in total, however many rows it has.
  ///
  /// Bounded on purpose: a per-row delay makes a twelve-row list elegant and a
  /// sixty-row list insufferable. See [staggerFor].
  static const staggerWindow = Duration(milliseconds: 220);

  // --------------------------------------------------------------------
  // Curves
  // --------------------------------------------------------------------

  /// Everything that arrives and stops. Decelerating, no overshoot.
  static const settle = Curves.easeOutCubic;

  /// Something leaving. Slightly faster out than in, so exits do not linger.
  static const leave = Curves.easeInCubic;

  /// Two-way motion that has to feel symmetrical — a drawer, a pane.
  static const both = Curves.easeInOutCubic;

  /// A gesture returning to rest after being released.
  ///
  /// The obvious choice is `easeOutBack`, which overshoots and springs — and
  /// which `docs/BRAND.md` rule 3 rules out by name. So this is the same
  /// deceleration as [settle]; the elasticity comes from the gesture tracking
  /// the finger, not from the curve.
  static const snapBack = Curves.easeOutCubic;

  // --------------------------------------------------------------------
  // The reduce-motion gate
  // --------------------------------------------------------------------

  /// True when the platform asks for reduced motion.
  ///
  /// On iOS this is Settings → Accessibility → Motion → Reduce Motion; on
  /// Android it is Remove animations in developer or accessibility settings.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// The duration to actually use.
  ///
  /// Returns exactly [Duration.zero] under reduce-motion rather than something
  /// small, because a 40ms animation is still an animation and G2 is explicit
  /// that shortening is not disabling.
  static Duration duration(BuildContext context, [Duration value = base]) =>
      reduced(context) ? Duration.zero : value;

  /// The curve to use. Linear under reduce-motion, where it will never be seen
  /// anyway, but a curve on a zero duration is a needless multiplication.
  static Curve curve(BuildContext context, [Curve value = settle]) =>
      reduced(context) ? Curves.linear : value;

  /// The delay for row [index] of a staggered list.
  ///
  /// The whole sequence finishes within [staggerWindow] no matter how many rows
  /// there are, so a long list does not turn into a slow reveal. Rows past
  /// [visibleCap] get no delay at all — they are below the fold, and animating
  /// something nobody is looking at is work a cheap phone should not do.
  static Duration staggerFor(BuildContext context, int index, {int visibleCap = 12}) {
    if (reduced(context) || index >= visibleCap) return Duration.zero;
    final step = staggerWindow.inMilliseconds / visibleCap;
    return Duration(milliseconds: (step * index).round());
  }
}

/// What the phone is allowed to do with its vibration motor.
///
/// The rule behind the list: **haptics confirm, they do not decorate.** Every
/// entry here fires in response to something the user did, at the moment its
/// result becomes true. Nothing fires on scroll, on arrival of someone else's
/// message, or on anything the user did not cause — a buzz for an incoming
/// message is what notifications are for, and doubling it is how an app becomes
/// the one that will not stop vibrating.
///
/// All of it is suppressed under reduce-motion. That is a slight
/// over-reach — the setting is about motion, not vibration — but the two
/// settings travel together for the people who need either, and a user who
/// asked for less stimulation did not mean "except in your hands".
abstract final class SakinaHaptics {
  static bool _allowed(BuildContext context) => !SakinaMotion.reduced(context);

  /// A message left the phone. The most-repeated interaction in the product,
  /// so it gets the lightest possible tick — anything heavier becomes fatigue
  /// by the fiftieth message of the evening.
  static void sent(BuildContext context) {
    if (_allowed(context)) HapticFeedback.lightImpact();
  }

  /// A gesture crossed the point where releasing it will do something.
  ///
  /// This is the highest-value haptic in the app: it lets someone swipe to
  /// reply without watching the screen, because the phone tells their thumb
  /// when to let go. `selectionClick` is the quietest option and the right one.
  static void threshold(BuildContext context) {
    if (_allowed(context)) HapticFeedback.selectionClick();
  }

  /// A long press opened something. Matches the platform convention that a
  /// long press is confirmed by feel rather than by waiting.
  static void pressed(BuildContext context) {
    if (_allowed(context)) HapticFeedback.mediumImpact();
  }

  /// Something the user tried did not work. Heavier, because it is rare and it
  /// needs to be distinguishable from [sent] without looking.
  static void failed(BuildContext context) {
    if (_allowed(context)) HapticFeedback.heavyImpact();
  }
}

/// Telegram's page transition: the incoming screen slides the **full width**
/// in from the trailing edge, the outgoing one parallaxes a third of the way
/// out behind it under a soft edge shadow, and a drag from the leading edge
/// takes it back.
///
/// This delegates to [CupertinoPageTransitionsBuilder] rather than
/// reproducing it. Three reasons, heaviest first:
///
///  1. **The back-swipe is the point, and it is not a curve.** It is a drag
///     that takes the route's animation over from the controller, hands it
///     back on release, flies the heroes in whichever direction the finger
///     settles on, and cancels cleanly if it changes its mind. Flutter already
///     ships that, correct, and installs it from this builder on *every*
///     platform — the gesture is not iOS-gated, only the habit of registering
///     the builder is. Rewriting it would mean shipping a worse version of
///     something people already have muscle memory for.
///  2. **G10, convention.** `docs/UX.md` copies Telegram's chrome because
///     familiarity is free adoption, and Telegram's own transition on both
///     platforms *is* this one: full-width slide, parallax underneath, edge
///     drag to return.
///  3. What it replaces was an 18% slide, which read as a twitch rather than
///     as arriving from somewhere.
///
/// What stays ours is the gate. Cupertino's builder has no reduce-motion path,
/// so registering it raw — which is what iOS and macOS did until now — meant
/// the platform whose users are most likely to have the setting switched on
/// was the one platform that ignored it.
///
/// Direction comes from [Directionality], not from a hardcoded left, so this
/// is already right if Sakina ships a Perso-Arabic script — an open question
/// in `docs/BRAND.md`. Cupertino handles that itself; [_EdgeFlingBack] has to
/// be told.
class SakinaPageTransitions extends PageTransitionsBuilder {
  const SakinaPageTransitions();

  /// The width of the strip that a back drag can start in.
  ///
  /// Matches Cupertino's own `_kBackGestureWidth`, so the target does not move
  /// under someone's thumb when reduce-motion changes which implementation is
  /// in play.
  static const double edgeWidth = 20;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (SakinaMotion.reduced(context)) {
      // No movement at all: the route swaps. Returning the child unwrapped is
      // the only way to be sure of that — a zero-duration controller still
      // rebuilds through the tween.
      //
      // Except that swiping back is navigation, not decoration. Someone who
      // asked for less movement did not ask to lose a way out of a screen, so
      // the edge keeps working — as a discrete fling rather than a drag that
      // follows the finger, since following the finger is the motion that was
      // turned off.
      //
      // Not on a fullscreen dialog: that route has no back-swipe on the
      // animated path either, and the two paths disagreeing about which
      // gestures exist is how a setting turns into a different app.
      return route.fullscreenDialog ? child : _EdgeFlingBack(child: child);
    }

    return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// A leading-edge strip that pops the route on a decisive outward fling.
///
/// The reduce-motion stand-in for the interactive back gesture. Deliberately
/// discrete: nothing tracks the finger and nothing animates. The fling either
/// clears the threshold and the route is gone, or it does not and nothing at
/// all happened — which is the honest reduce-motion reading of a gesture whose
/// whole feedback is normally movement.
class _EdgeFlingBack extends StatelessWidget {
  const _EdgeFlingBack({required this.child});

  final Widget child;

  /// Logical pixels per second, measured on the horizontal axis.
  ///
  /// Higher than Flutter's own ~365 fling boundary on purpose: this strip
  /// overlaps where a swipe-to-reply on the leftmost bubbles begins, and
  /// between the two mistakes, a gesture that does nothing is much cheaper
  /// than one that leaves the chat.
  static const double _flingVelocity = 700;

  @override
  Widget build(BuildContext context) {
    // +1 when back is to the right of the start edge, -1 when the language
    // runs the other way.
    final outward = Directionality.of(context) == TextDirection.rtl ? -1 : 1;

    return Stack(
      // The page must keep the tight constraints the navigator gave it; a
      // loose Stack would let a Scaffold size itself to its own content.
      fit: StackFit.expand,
      children: [
        child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: SakinaPageTransitions.edgeWidth,
          child: GestureDetector(
            // Invisible and unlabelled by design. The route carries a back
            // button in the corner, and that is the affordance a screen reader
            // should find — a 20px strip announcing itself would be noise.
            excludeFromSemantics: true,
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = (details.primaryVelocity ?? 0) * outward;
              if (velocity > _flingVelocity) {
                unawaited(Navigator.of(context).maybePop());
              }
            },
          ),
        ),
      ],
    );
  }
}

/// A page route timed from the vocabulary instead of from Flutter's defaults.
///
/// [MaterialPageRoute] hardcodes 300ms and Cupertino's route uses considerably
/// more; neither number is in `docs/MOTION.md`, and that document is only true
/// if the timings it names are the timings that actually run. 320ms is exactly
/// what [SakinaMotion.long] is for — "the longest thing we do, a full-screen
/// transition on a slow device".
///
/// Only the timing. Which transition, the parallax, the shadow and the gesture
/// all still come from the theme, so no single route gets to disagree with the
/// app about how navigation looks.
class SakinaPageRoute<T> extends MaterialPageRoute<T> {
  SakinaPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => SakinaMotion.long;

  @override
  Duration get reverseTransitionDuration => SakinaMotion.long;
}

/// Fades and slides a child in once, on first build.
///
/// Used for staggered list entry. Deliberately a one-shot: it animates when the
/// widget is created and never again, so a list that rebuilds because a message
/// arrived does not re-run the whole entrance.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 0.06,
    this.scaleFrom = 1.0,
    this.duration = SakinaMotion.base,
  });

  final Widget child;
  final Duration delay;

  /// How far it travels, as a fraction of its own height.
  final double offset;

  /// Starting scale. 1.0 means no scaling — the usual case for a list row.
  ///
  /// A2 uses a value slightly under 1 so a sent message grows as it rises,
  /// which is what makes it read as lifting out of the composer rather than
  /// sliding in from off-screen.
  final double scaleFrom;

  final Duration duration;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Read reduce-motion here rather than in initState: MediaQuery is not
    // available until dependencies resolve, and asking too early throws.
    if (SakinaMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: SakinaMotion.settle);
    Widget child = SlideTransition(
      position: Tween(begin: Offset(0, widget.offset), end: Offset.zero).animate(curved),
      child: widget.child,
    );
    if (widget.scaleFrom != 1.0) {
      child = ScaleTransition(
        scale: Tween(begin: widget.scaleFrom, end: 1.0).animate(curved),
        child: child,
      );
    }
    return FadeTransition(opacity: curved, child: child);
  }
}
