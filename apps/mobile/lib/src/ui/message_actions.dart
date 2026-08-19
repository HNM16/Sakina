import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../layout.dart';
import '../motion.dart';
import '../theme.dart';

/// What a long press on a message offers.
///
/// Deliberately a small set: everything here works today. Forward, delete and
/// reactions are D2, D4 and D5 in `docs/BACKLOG.md` and will slot in beside
/// these — the menu is built as a list so a fourth and fifth entry cost
/// nothing.
enum MessageAction { reply, copy }

/// A long-press menu that lifts the message off a blurred page.
///
/// The pattern is iOS's context menu and Telegram's message menu, and it is
/// worth copying precisely because it solves a real problem: it shows *which*
/// message the actions apply to. A plain bottom sheet loses that — you long-
/// press one bubble in a fast-moving group, the list scrolls, and the sheet is
/// now about a message you cannot see.
///
/// So the pressed bubble is redrawn in place over the blur, and everything else
/// recedes.
Future<MessageAction?> showMessageActions(
  BuildContext context, {
  required Widget bubble,
  required Rect anchor,
  required bool canReply,
}) {
  SakinaHaptics.pressed(context);

  return Navigator.of(context, rootNavigator: true).push<MessageAction>(
    _MessageActionsRoute(
      bubble: bubble,
      anchor: anchor,
      canReply: canReply,
      // Captured here: the route builds outside the caller's subtree, so
      // Theme, Directionality and L10n have to be carried across rather than
      // looked up on the other side.
      theme: Theme.of(context),
      l10n: L10n.of(context),
      reduced: SakinaMotion.reduced(context),
    ),
  );
}

class _MessageActionsRoute extends PopupRoute<MessageAction> {
  _MessageActionsRoute({
    required this.bubble,
    required this.anchor,
    required this.canReply,
    required this.theme,
    required this.l10n,
    required this.reduced,
  });

  final Widget bubble;
  final Rect anchor;
  final bool canReply;
  final ThemeData theme;
  final L10n l10n;
  final bool reduced;

  @override
  Color? get barrierColor => null; // the blur is the barrier

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : SakinaMotion.travel;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) {
    return Theme(
      data: theme,
      child: _MessageActionsLayer(
        bubble: bubble,
        anchor: anchor,
        canReply: canReply,
        l10n: l10n,
        animation: animation,
      ),
    );
  }
}

class _MessageActionsLayer extends StatelessWidget {
  const _MessageActionsLayer({
    required this.bubble,
    required this.anchor,
    required this.canReply,
    required this.l10n,
    required this.animation,
  });

  final Widget bubble;
  final Rect anchor;
  final bool canReply;
  final L10n l10n;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final screen = MediaQuery.of(context).size;
    final curved = CurvedAnimation(parent: animation, curve: SakinaMotion.settle);

    final actions = <(MessageAction, IconData, String)>[
      if (canReply) (MessageAction.reply, Icons.reply, l10n.t('reply')),
      (MessageAction.copy, Icons.copy_outlined, l10n.t('copy')),
    ];

    // The menu goes below the bubble when there is room and above when there is
    // not, so a message near the bottom of the screen does not push its own
    // menu off it.
    final menuHeight = actions.length * SakinaLayout.tapTarget + 16;
    final below = anchor.bottom + 10;
    final fitsBelow = below + menuHeight < screen.height - layout.safeArea.bottom;
    final menuTop = fitsBelow ? below : anchor.top - menuHeight - 10;

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 14 * curved.value,
                  sigmaY: 14 * curved.value,
                ),
                child: Container(
                  // A tint under the blur. Blur alone does not separate a light
                  // bubble from a light page, and this menu has to work in both
                  // themes.
                  // ignore: deprecated_member_use
                  color: Colors.black.withOpacity(0.28 * curved.value),
                ),
              ),
            ),
          ),

          // The message itself, redrawn where it already was and lifted very
          // slightly. Any more scale and it stops being the same object.
          Positioned(
            left: anchor.left,
            top: anchor.top,
            width: anchor.width,
            child: Transform.scale(
              scale: 1 + 0.03 * curved.value,
              alignment: Alignment.center,
              child: IgnorePointer(child: bubble),
            ),
          ),

          Positioned(
            left: layout.gutter,
            right: layout.gutter,
            top: menuTop.clamp(layout.safeArea.top + 8, screen.height - menuHeight - 8),
            child: Opacity(
              opacity: curved.value,
              child: Transform.scale(
                scale: 0.94 + 0.06 * curved.value,
                alignment: fitsBelow ? Alignment.topCenter : Alignment.bottomCenter,
                child: Material(
                  color: palette.bubbleTheirs,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (action, icon, label) in actions)
                        InkWell(
                          onTap: () => Navigator.of(context).pop(action),
                          child: Container(
                            height: SakinaLayout.tapTarget,
                            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                            child: Row(
                              children: [
                                Icon(icon, size: 20, color: palette.muted),
                                SizedBox(width: layout.gutter * 0.75),
                                Text(label),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a message so a long press opens [showMessageActions].
///
/// Measures its own position at press time rather than caching it, because in a
/// live conversation the list has almost certainly moved since it was built.
class LongPressActions extends StatefulWidget {
  const LongPressActions({
    super.key,
    required this.child,
    required this.canReply,
    required this.onReply,
    required this.copyText,
  });

  final Widget child;
  final bool canReply;
  final VoidCallback onReply;

  /// Null when there is nothing to copy — a photo with no caption.
  final String? copyText;

  @override
  State<LongPressActions> createState() => _LongPressActionsState();
}

class _LongPressActionsState extends State<LongPressActions> {
  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final origin = box.localToGlobal(Offset.zero);
    final anchor = origin & box.size;

    final action = await showMessageActions(
      context,
      bubble: widget.child,
      anchor: anchor,
      canReply: widget.canReply,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case MessageAction.reply:
        widget.onReply();
      case MessageAction.copy:
        final text = widget.copyText;
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(L10n.of(context).t('copied'))),
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _open,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
