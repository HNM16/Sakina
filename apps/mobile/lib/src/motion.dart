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

/// Forward slides in from the trailing edge; back slides out to it.
///
/// Flutter's default builders use the same animation in both directions, which
/// leaves the app without a spatial model — nothing tells you whether you went
/// deeper or came back. Direction is the cheapest way to make an interface feel
/// navigable rather than teleported.
///
/// Direction-aware rather than left-to-right hardcoded, because the same code
/// has to be right if Sakina ever ships an RTL language. Perso-Arabic is
/// already listed as an open question in `docs/BRAND.md`.
class SakinaPageTransitions extends PageTransitionsBuilder {
  const SakinaPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Under reduce-motion, the route swaps with no movement at all. Returning
    // the child unwrapped is the only way to be sure of that — a zero-duration
    // controller still rebuilds through the tween.
    if (SakinaMotion.reduced(context)) return child;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final enter = Offset(isRtl ? -0.18 : 0.18, 0);
    // The outgoing page moves a third as far. Parallax: the thing being covered
    // should feel further away than the thing covering it.
    final exit = Offset(isRtl ? 0.06 : -0.06, 0);

    return SlideTransition(
      position: Tween(begin: enter, end: Offset.zero)
          .chain(CurveTween(curve: SakinaMotion.settle))
          .animate(animation),
      child: SlideTransition(
        position: Tween(begin: Offset.zero, end: exit)
            .chain(CurveTween(curve: SakinaMotion.both))
            .animate(secondaryAnimation),
        child: FadeTransition(
          // Fades in over the first half only, so the page is solid well before
          // it stops moving. A fade that runs the whole way reads as sluggish.
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
          child: child,
        ),
      ),
    );
  }
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
