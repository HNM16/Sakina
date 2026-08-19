import 'package:flutter/material.dart';

import '../layout.dart';
import '../motion.dart';
import '../theme.dart';

/// A shimmering placeholder block.
///
/// The shimmer is the part of a skeleton that usually gets accessibility wrong:
/// it is a looping animation, so under reduce-motion it must stop entirely
/// rather than slow down. Here that means a flat block in the same colour —
/// still a skeleton, still communicating "something is coming", with nothing
/// moving.
///
/// It is also the part that usually gets *performance* wrong. One
/// [AnimationController] per skeleton block on a twelve-row list is twelve
/// controllers ticking every frame on a phone that has better things to do, so
/// [Skeleton] takes its animation from an inherited [SkeletonPulse] and the
/// whole screen shares one.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  /// `double.infinity` is fine and common — a line of text filling its row.
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = SakinaPalette.of(context);
    final pulse = SkeletonPulse.maybeOf(context);

    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.line,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (pulse == null || SakinaMotion.reduced(context)) return block;

    return FadeTransition(
      // Never fades to nothing. A block that disappears and reappears reads as
      // flashing; one that breathes between 0.45 and 1 reads as loading.
      opacity: pulse.drive(Tween(begin: 0.45, end: 1.0)),
      child: block,
    );
  }
}

/// Drives every [Skeleton] beneath it from a single controller.
///
/// Wrap a loading screen in one of these. Without it the skeletons render
/// static, which is a correct-if-plain fallback rather than a failure.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseScope>()?.animation;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.pulse,
  );

  late final Animation<double> _animation =
      CurvedAnimation(parent: _controller, curve: SakinaMotion.both);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // reverse: true rather than repeat(): a sawtooth pulse snaps back to dim at
    // the top of each cycle, which is exactly the flashing this is meant to
    // avoid.
    if (!SakinaMotion.reduced(context)) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PulseScope(animation: _animation, child: widget.child);
}

class _PulseScope extends InheritedWidget {
  const _PulseScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_PulseScope oldWidget) => oldWidget.animation != animation;
}

/// What the chat list looks like while SQLite is opening.
///
/// Sized to the rows it replaces — same avatar diameter, same two lines, same
/// row height — so the real list does not shift anything when it lands. A
/// skeleton whose geometry does not match its content is worse than none: it
/// replaces "nothing is happening" with "everything jumped".
class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key, this.rows = 7});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);

    return SkeletonPulse(
      child: ListView.builder(
        // Nothing here scrolls meaningfully; it exists for a few hundred
        // milliseconds and must not steal a fling that was meant for the real
        // list underneath it.
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.gutter,
            vertical: 4,
          ),
          child: SizedBox(
            height: SakinaLayout.tapTarget + 8,
            child: Row(
              children: [
                Skeleton(
                  width: layout.avatarSize,
                  height: layout.avatarSize,
                  radius: layout.avatarSize / 2,
                ),
                SizedBox(width: layout.gutter * 0.75),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Varied widths, from a fixed pattern rather than a random
                      // number: a skeleton that reshuffles on every rebuild is a
                      // distraction, and guardrail G17 rules out randomised
                      // jitter used to look human.
                      Skeleton(width: 120 + (index % 3) * 34, height: 13),
                      const SizedBox(height: 7),
                      Skeleton(width: 180 + (index % 4) * 26, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a conversation looks like before its history is read off disk.
///
/// Alternating sides and varied widths, because a column of identical grey
/// rectangles does not read as a conversation — and the point of a skeleton is
/// to say what is coming, not merely that something is.
class MessageListSkeleton extends StatelessWidget {
  const MessageListSkeleton({super.key, this.rows = 8});

  final int rows;

  /// A fixed pattern: width fraction, and whether it is on the sending side.
  static const _shape = <(double, bool)>[
    (0.55, false),
    (0.34, true),
    (0.72, false),
    (0.46, true),
    (0.60, true),
    (0.38, false),
    (0.66, true),
    (0.50, false),
  ];

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);
    final available = layout.detailPaneWidth - layout.gutter * 2;

    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(vertical: layout.gap),
        itemCount: rows,
        itemBuilder: (context, index) {
          final (fraction, mine) = _shape[index % _shape.length];
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 3),
              child: Skeleton(
                width: (available * fraction).clamp(80.0, layout.bubbleMaxWidth(available)),
                height: 38,
                radius: 16,
              ),
            ),
          );
        },
      ),
    );
  }
}
