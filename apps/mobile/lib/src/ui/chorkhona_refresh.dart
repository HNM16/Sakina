// MOTION: ЧАРХ — the mark steps while a refresh is in flight.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// Pull down and the chorkhona draws itself.
///
/// A brand moment placed where people already pull, which is the cheapest kind
/// there is — no new gesture to teach, no new affordance on screen. The mark
/// is already a `CustomPainter`, so all this adds is extracting a fraction of
/// each stroke instead of the whole thing.
///
/// **On the choice of [CupertinoSliverRefreshControl] on every platform.**
/// Material's `RefreshIndicator` is not extensible — it draws its own circle
/// and exposes no pull fraction, so there is nowhere to put a custom painter.
/// The Cupertino control is the only Flutter API that hands the builder the
/// pull extent, and it is not iOS-specific in behaviour, only in origin. The
/// cost is that the list follows the finger instead of a circle floating over
/// it, which is a real deviation from Android convention — accepted here
/// because `docs/UX.md` reserves convention for *navigation and layout*, and
/// this is neither.
class ChorkhonaRefresh extends StatelessWidget {
  const ChorkhonaRefresh({super.key, required this.onRefresh});

  final Future<void> Function() onRefresh;

  /// How far to pull before releasing does something.
  static const double triggerDistance = 96;

  /// How much room the indicator occupies while it is working.
  static const double indicatorExtent = 68;

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverRefreshControl(
      onRefresh: onRefresh,
      refreshTriggerPullDistance: triggerDistance,
      refreshIndicatorExtent: indicatorExtent,
      builder: (context, mode, pulledExtent, triggerPull, indicatorSize) {
        // Progress is what the user has actually pulled, before release. Once
        // the refresh is running the mark is complete and spins instead.
        final progress = (pulledExtent / triggerPull).clamp(0.0, 1.0);
        final working = mode == RefreshIndicatorMode.refresh ||
            mode == RefreshIndicatorMode.armed;

        return Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _DrawingMark(
              progress: working ? 1 : progress,
              spinning: mode == RefreshIndicatorMode.refresh,
              // Fades out as the list settles back, so a cancelled pull does
              // not leave the mark hanging at full strength.
              opacity: mode == RefreshIndicatorMode.done ? 0 : 1,
            ),
          ),
        );
      },
    );
  }
}

class _DrawingMark extends StatefulWidget {
  const _DrawingMark({
    required this.progress,
    required this.spinning,
    required this.opacity,
  });

  final double progress;
  final bool spinning;
  final double opacity;

  @override
  State<_DrawingMark> createState() => _DrawingMarkState();
}

class _DrawingMarkState extends State<_DrawingMark> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: SakinaMotion.charkhStep * SakinaMotion.charkhPositions,
  );

  @override
  void didUpdateWidget(_DrawingMark old) {
    super.didUpdateWidget(old);
    _syncSpin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  void _syncSpin() {
    // Under reduce-motion the mark still draws as you pull — that is direct
    // response to a finger, not decoration — but it never spins on its own.
    final shouldSpin = widget.spinning && !SakinaMotion.reduced(context);
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  /// Turn, then hold — see [TurningMark], which is the same curve for the
  /// standalone indicator. Shared by shape rather than by code because this one
  /// also has to blend with the pull-draw progress underneath it.
  double _charkhAngle(double value) {
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
    final palette = SakinaPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    return AnimatedOpacity(
      opacity: widget.opacity,
      duration: SakinaMotion.duration(context, SakinaMotion.quick),
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => Transform.rotate(
          // ЧАРХ: eight discrete 45 degree positions, each held. A smooth spin
          // on a four-fold symmetric mark looks almost static; stepping makes
          // it visibly turn and alternates the silhouette square/diamond.
          angle: _charkhAngle(_spin.value),
          child: CustomPaint(
            size: const Size.square(34),
            painter: _ChorkhonaStrokePainter(
              progress: widget.progress,
              stroke: accent,
              core: palette.saffron,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the chorkhona one stroke at a time.
///
/// Each tier is a closed path whose outline is extracted up to a fraction of
/// its length with `PathMetric.extractPath`, so the square genuinely draws
/// itself rather than fading in. The tiers run in sequence — outer, the turned
/// middle, inner, then the core lands — which reads as the skylight being
/// built from the roof inwards.
class _ChorkhonaStrokePainter extends CustomPainter {
  _ChorkhonaStrokePainter({
    required this.progress,
    required this.stroke,
    required this.core,
  });

  final double progress;
  final Color stroke;
  final Color core;

  /// Where each tier starts and ends within the overall 0..1 pull.
  static const _tiers = <(double, double, double, double)>[
    // (start, end, halfSize, rotation)
    (0.00, 0.40, 38, 0),
    (0.35, 0.72, 26, 0.7853981633974483),
    (0.68, 0.92, 17, 0),
  ];

  /// The fraction of [outer]..[inner] that [progress] has covered.
  double _phase(double start, double end) =>
      ((progress - start) / (end - start)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    final centre = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * unit
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = stroke;

    for (final (start, end, half, rotation) in _tiers) {
      final t = _phase(start, end);
      if (t <= 0) continue;

      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: half * 2 * unit,
        height: half * 2 * unit,
      );
      final full = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(3 * unit)));

      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(rotation);

      if (t >= 1) {
        canvas.drawPath(full, paint);
      } else {
        // extractPath walks the outline, so a partial square is a square being
        // drawn rather than a square being faded in.
        for (final metric in full.computeMetrics()) {
          canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
        }
      }
      canvas.restore();
    }

    // The core arrives last and scales in, so completing the pull has a moment.
    final coreT = _phase(0.88, 1.0);
    if (coreT > 0) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(0.7853981633974483);
      final side = 16 * unit * coreT;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: side, height: side),
          Radius.circular(2 * unit),
        ),
        Paint()..color = core,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ChorkhonaStrokePainter old) =>
      old.progress != progress || old.stroke != stroke || old.core != core;
}
