// MOTION: ТОБ — the light pass, once, when something becomes true.
// MOTION: НАФАС — the breath, while something is in doubt.
// MOTION: ЧАРХ — the turn, while something is working.
//
// The three primitives themselves. docs/MOTION.md is the argument for why
// these and not others; this file is what they are.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The widget layer of Sakina's motion language. `motion.dart` holds the
/// numbers; this holds the three things they animate.
///
/// All three come from one fact about our own mark: a chorkhona is not a shape,
/// it is *an opening that lets light into a house*. Every other messenger
/// expresses change by moving something. We light it — which is both the more
/// distinctive choice and the quieter one, and quiet is the brand.
///
///   ТОБ    a single band of light crossing once, when something becomes true
///   НАФАС  the thing being waited on breathes
///   ЧАРХ   the mark turns 45° at a time and holds
///
/// See `docs/MOTION.md`.

// ---------------------------------------------------------------------------
// ТОБ — the light pass
// ---------------------------------------------------------------------------

/// A single band of firuza crossing [child] at 45°, once.
///
/// Fires when [trigger] changes, so a caller flips a value at the moment
/// something becomes true — a message acked, an upload finished — and the pass
/// runs itself.
///
/// **This is not a shimmer, and the difference is the entire point.** A shimmer
/// loops while you wait, which the design-tells catalogue rightly calls a
/// cliché when used as decoration. This runs once, on success, and never while
/// waiting. If it ever loops, it stops meaning "arrived" and we have built the
/// tell we were avoiding.
class LightPass extends StatefulWidget {
  const LightPass({
    super.key,
    required this.child,
    required this.trigger,
    this.borderRadius = 16,
    this.enabled = true,
  });

  final Widget child;

  /// Any value. When it changes to something new, the pass runs.
  final Object? trigger;

  /// Matches the surface being crossed, so light does not spill past a corner.
  final double borderRadius;

  final bool enabled;

  @override
  State<LightPass> createState() => _LightPassState();
}

class _LightPassState extends State<LightPass> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.tob,
  );

  @override
  void didUpdateWidget(LightPass old) {
    super.didUpdateWidget(old);
    if (old.trigger == widget.trigger) return;
    if (!widget.enabled) return;
    // Nothing at all under reduce-motion. The information was never in the
    // motion — the tick that lands alongside it carries the meaning — so
    // removing it costs the user nothing.
    if (SakinaMotion.reduced(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // Painting nothing at rest, which is almost always, so a
                // conversation full of settled bubbles costs no paint work.
                if (_controller.value == 0 || _controller.isCompleted) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: CustomPaint(
                    painter: _LightPassPainter(
                      progress: _controller.value,
                      colour: accent,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LightPassPainter extends CustomPainter {
  _LightPassPainter({required this.progress, required this.colour});

  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    // Eased here rather than by the controller, so the envelope below stays on
    // a linear clock and the fade in and out are symmetrical.
    final t = SakinaMotion.settle.transform(progress);

    // Travel is the sum of the sides: the band enters at one corner and leaves
    // at the opposite one, which is what makes the direction read as 45°
    // regardless of how wide or tall the surface is.
    final travel = size.width + size.height;
    final band = travel * SakinaMotion.tobBand;
    final centre = -band + t * (travel + band * 2);

    // The gradient axis runs along the diagonal, so the lit stripe lies across
    // it — a band at 45°, the chorkhona's own angle.
    final from = Offset(centre - band / 2, centre - band / 2);
    final to = Offset(centre + band / 2, centre + band / 2);

    // Fades in over the first fifth and out over the last, so the band never
    // appears or vanishes mid-surface.
    final envelope = progress < 0.18
        ? progress / 0.18
        : progress > 0.82
            ? (1 - progress) / 0.18
            : 1.0;

    // ignore: deprecated_member_use
    final lit = colour.withOpacity(0.62 * envelope.clamp(0.0, 1.0));
    // ignore: deprecated_member_use
    final clear = colour.withOpacity(0);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          from,
          to,
          [clear, lit, clear],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_LightPassPainter old) =>
      old.progress != progress || old.colour != colour;
}

// ---------------------------------------------------------------------------
// НАФАС — the breath
// ---------------------------------------------------------------------------

/// Breathes [child] while [waiting].
///
/// A spinner is an object that is *not* the thing you care about, placed next
/// to the thing you care about, moving. Breathing lets the object in doubt say
/// so itself — one fewer element on screen, and nothing competing with the
/// conversation for attention.
///
/// Under reduce-motion it holds a single dimmed opacity, so "waiting" stays
/// legible with nothing moving. Reduced motion is not reduced information.
class Breathing extends StatefulWidget {
  const Breathing({super.key, required this.child, required this.waiting});

  final Widget child;
  final bool waiting;

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.nafas,
  );

  @override
  void didUpdateWidget(Breathing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final shouldBreathe = widget.waiting && !SakinaMotion.reduced(context);
    if (shouldBreathe && !_controller.isAnimating) {
      // Alternating rather than looping: a sawtooth snaps back to dim at the
      // top of every cycle, and that snap is exactly the flashing this avoids.
      _controller.repeat(reverse: true);
    } else if (!shouldBreathe && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.waiting) return widget.child;
    if (SakinaMotion.reduced(context)) {
      return Opacity(opacity: SakinaMotion.nafasFloor + 0.17, child: widget.child);
    }
    return FadeTransition(
      opacity: _controller.drive(
        Tween(begin: SakinaMotion.nafasFloor, end: 1.0)
            .chain(CurveTween(curve: SakinaMotion.both)),
      ),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// ЧАРХ — the turn
// ---------------------------------------------------------------------------

/// The chorkhona turning 45° at a time.
///
/// Every loading indicator in the world spins smoothly. Ours steps, because the
/// mark is squares set at 45° to each other and 45° is the smallest rotation
/// that returns the shape to a face. It reads as deliberate rather than
/// anxious — the difference between a spinner and a clock.
///
/// The symmetry is also why stepping is not merely a stylistic choice: the mark
/// has four-fold symmetry, so a smooth spin would look almost static. Stepping
/// makes it visibly turn, and the silhouette alternates square and diamond.
///
/// Used only where there is no object to breathe — app-level loading, or a
/// refresh already in flight. Where there *is* one, use [Breathing].
class TurningMark extends StatefulWidget {
  const TurningMark({super.key, this.size = 40, this.working = true, this.label});

  final double size;
  final bool working;

  /// Shown under the mark when the platform asks for reduced motion.
  ///
  /// A loading indicator that neither moves nor says anything is not an
  /// indicator, so the state has to be carried by words when it cannot be
  /// carried by movement.
  final String? label;

  @override
  State<TurningMark> createState() => _TurningMarkState();
}

class _TurningMarkState extends State<TurningMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.charkhStep * SakinaMotion.charkhPositions,
  );

  @override
  void didUpdateWidget(TurningMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final shouldTurn = widget.working && !SakinaMotion.reduced(context);
    if (shouldTurn && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldTurn && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Turn, then hold. The eased portion is [SakinaMotion.charkhTurnFraction] of
  /// each step; the rest of the step the mark stands still, which is what makes
  /// it read as stepping rather than as a jerky spin.
  double _angleFor(double value) {
    final positions = SakinaMotion.charkhPositions;
    final scaled = value * positions;
    final index = scaled.floor();
    final within = scaled - index;
    final turn = within < SakinaMotion.charkhTurnFraction
        ? SakinaMotion.both.transform(within / SakinaMotion.charkhTurnFraction)
        : 1.0;
    return (index + turn) * (math.pi / 4);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final still = SakinaMotion.reduced(context);

    final mark = still
        ? ChorkhonaMark(size: widget.size)
        : AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.rotate(
              angle: _angleFor(_controller.value),
              child: child,
            ),
            // Built once and rotated, rather than rebuilt every frame — the
            // mark is a CustomPaint and there is no reason to re-run it eight
            // times a second.
            child: ChorkhonaMark(size: widget.size),
          );

    if (!still || label == null) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 10),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: SakinaPalette.of(context).muted),
        ),
      ],
    );
  }
}
