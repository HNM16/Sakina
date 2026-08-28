import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The three dots that mean somebody is typing.
///
/// Plain text ("менависад…") is what was here before, and text reads as a
/// status bar. Movement is what makes it read as a person at the other end,
/// which is the entire information content of the indicator.
///
/// Under reduce-motion it falls back to three static dots rather than to
/// nothing: the *presence* of the indicator is the message, and only the
/// animation is decoration.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.size = 5, this.color});

  final double size;
  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.typing,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!SakinaMotion.reduced(context)) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opacity for dot [index] at animation position [t].
  ///
  /// Each dot runs the same curve a third of a cycle apart, so the highlight
  /// travels left to right. Opacity rather than translation on purpose: a dot
  /// that moves has to be given vertical room, which would make the app bar
  /// taller whenever someone types.
  double _opacityFor(int index, double t) {
    final phase = (t - index * 0.22) % 1.0;
    // Bright for the first third of its own phase, then dim. Sine keeps the
    // transition soft without a second curve.
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.32 + 0.68 * Curves.easeInOut.transform(wave.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SakinaPalette.of(context).muted;
    final still = SakinaMotion.reduced(context);

    Widget dot(double opacity) => Container(
          width: widget.size,
          height: widget.size,
          margin: EdgeInsets.symmetric(horizontal: widget.size * 0.28),
          decoration: BoxDecoration(
            // withOpacity rather than withValues: withValues needs a newer
            // Flutter than pubspec's floor allows.
            // ignore: deprecated_member_use
            color: color.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        );

    if (still) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [dot(0.9), dot(0.7), dot(0.5)],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i += 1) dot(_opacityFor(i, _controller.value)),
        ],
      ),
    );
  }
}

/// The unread count, which counts down to nothing when a chat is read.
///
/// Clearing a chat is a small satisfying moment and it deserves feedback.
/// Counting to zero and then collapsing is more satisfying than a badge
/// blinking out — and it is also more *informative*, because the shrink tells
/// you which row changed when several update at once.
///
/// Growing is instant, shrinking is animated: a new message should register
/// immediately, while the reward for reading can afford a fifth of a second.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      // begin is only read on the first build, so starting from 0 gives the
      // count-up when a badge first appears. On every later build
      // TweenAnimationBuilder animates from wherever it currently is to the new
      // end, which is what makes 12 -> 0 tick through the numbers rather than
      // cutting to nothing.
      tween: Tween(begin: 0, end: count.toDouble()),
      duration: SakinaMotion.duration(context, SakinaMotion.base),
      curve: SakinaMotion.curve(context),
      builder: (context, value, child) {
        // Gone entirely, rather than a zero-sized box still holding a slot.
        if (value <= 0.02) return const SizedBox.shrink();

        // ceil, not round: while shrinking from 1 to 0 it should still read
        // "1" until it has actually gone, rather than flicking to 0 halfway.
        final shown = value.ceil();

        // 1 for any count of one or more; ramps to 0 only across the final
        // unit, so the last of the badge shrinks away instead of vanishing at
        // full size.
        final tail = value.clamp(0.0, 1.0);

        return Opacity(
          opacity: tail,
          child: Transform.scale(
            scale: 0.55 + 0.45 * tail,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                shown > 999 ? '999+' : '$shown',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      // Tabular so a badge going 9 -> 10 does not change width
                      // mid-count and nudge the row it sits in.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
