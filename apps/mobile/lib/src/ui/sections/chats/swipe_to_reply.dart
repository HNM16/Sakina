import 'package:flutter/material.dart';

import '../../../motion.dart';
import '../../../theme.dart';

/// Drag a bubble sideways to reply to it.
///
/// The most-used gesture in modern messengers, and a textbook Nielsen #7 win:
/// an expert shortcut that costs beginners nothing, because a bubble that does
/// not get dragged behaves exactly as before.
///
/// The haptic at the threshold is the part that matters most. It lets someone
/// swipe without watching the screen — the phone tells the thumb when to let
/// go — which is how the gesture becomes muscle memory rather than something
/// you have to aim.
///
/// Follows the finger while dragging (with resistance past the threshold, so
/// there is a felt edge) and settles back with no overshoot, per brand rule 3.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;

  /// False in a channel a subscriber cannot post to — a gesture that leads to
  /// a composer they do not have is a promise the app cannot keep.
  final bool enabled;

  /// How far to drag before releasing triggers a reply.
  static const double threshold = 56;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: SakinaMotion.base,
  );

  double _offset = 0;
  bool _passed = false;

  /// True when this drag began in the strip the back gesture owns.
  ///
  /// The two gestures are the same gesture — a horizontal drag on a bubble —
  /// and in the leftmost 20px they both want it. Telegram resolves this the
  /// same way: the edge belongs to navigation, and a reply started there is
  /// not started at all. Leaving it to the arena would resolve it by tree
  /// depth, which means this widget wins and the user swipes at the edge to
  /// go back and gets a reply arrow instead.
  bool _fromBackEdge = false;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails details) {
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    // The back edge is the leading one, which is the right-hand side of the
    // screen in an RTL layout.
    _fromBackEdge = Directionality.of(context) == TextDirection.rtl
        ? x >= width - SakinaPageTransitions.edgeWidth
        : x <= SakinaPageTransitions.edgeWidth;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_fromBackEdge) return;

    // Direction-aware: in an RTL layout the reply gesture pulls the other way,
    // and hardcoding "drag right" would make it feel backwards.
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    var next = _offset + details.delta.dx * sign;

    if (next < 0) {
      next = 0;
    } else if (next > SwipeToReply.threshold) {
      // Rubber-banding past the threshold. Without it the bubble keeps sliding
      // and there is nothing to feel; with it, the gesture has an edge.
      next = SwipeToReply.threshold + (next - SwipeToReply.threshold) * 0.28;
    }

    final passed = next >= SwipeToReply.threshold;
    if (passed != _passed) {
      _passed = passed;
      // Only on the way in. Buzzing again when someone drags back under the
      // line would make an indecisive thumb feel like a fault.
      if (passed) SakinaHaptics.threshold(context);
    }

    setState(() => _offset = next);
  }

  void _onEnd(DragEndDetails details) {
    if (_fromBackEdge) {
      _fromBackEdge = false;
      return;
    }

    final fire = _passed;
    final from = _offset;

    _passed = false;
    _settle
      ..reset()
      ..duration = SakinaMotion.duration(context, SakinaMotion.base);

    void tick() {
      if (!mounted) return;
      setState(() {
        _offset = from * (1 - SakinaMotion.snapBack.transform(_settle.value));
      });
    }

    _settle.addListener(tick);
    _settle.forward().whenComplete(() {
      _settle.removeListener(tick);
      if (mounted) setState(() => _offset = 0);
    });

    // Fire on release rather than at the threshold: crossing the line is a
    // preview, letting go is the decision. That is what makes the gesture
    // cancellable, which is Nielsen #3.
    if (fire) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final palette = SakinaPalette.of(context);
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final reveal = (_offset / SwipeToReply.threshold).clamp(0.0, 1.0);

    return GestureDetector(
      // Horizontal only, and the vertical drag falls through to the list, so
      // scrolling a conversation never accidentally arms a reply.
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() {
        _offset = 0;
        _passed = false;
        _fromBackEdge = false;
      }),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // The arrow sits under the bubble and is revealed by the drag, rather
          // than travelling with it. It grows to full size exactly at the
          // threshold, so the visual and the haptic agree.
          Positioned.fill(
            child: Align(
              alignment: sign > 0
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Opacity(
                  opacity: reveal,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * reveal,
                    child: Icon(
                      Icons.reply,
                      size: 20,
                      color: reveal >= 1 ? palette.saffron : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_offset * sign, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// The bar above the composer showing what you are replying to.
///
/// Dismissible, because arming a reply by accident is the most likely failure
/// of the swipe gesture and there has to be a way out that is not "send it
/// anyway".
class ReplyPreview extends StatelessWidget {
  const ReplyPreview({
    super.key,
    required this.author,
    required this.preview,
    required this.onCancel,
  });

  final String author;
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = SakinaPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 2.5, height: 34, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// The quoted message drawn inside a bubble.
class QuotedMessage extends StatelessWidget {
  const QuotedMessage({
    super.key,
    required this.author,
    required this.preview,
    this.onTap,
  });

  final String author;
  final String preview;

  /// Jumps to the original. Null when it is not in the loaded history.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: accent, width: 2.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: accent, fontWeight: FontWeight.w600),
            ),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
