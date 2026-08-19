import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// The circle that identifies a chat.
///
/// Shared between the list row and the conversation's app bar because the A1
/// hero flies *this widget* between them: if the two ends drew the avatar
/// differently the flight would visibly morph, which is worse than no flight at
/// all. One widget, two sizes.
///
/// A group and a channel get a glyph rather than an initial. That is
/// information, not decoration — a channel you cannot reply in looks exactly
/// like a group until you try to type, and the icon is the only thing that
/// says so before you open it.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.chat,
    required this.selfId,
    required this.size,
  });

  final ChatSummary chat;
  final String selfId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = SakinaPalette.of(context);
    final title = chat.displayTitle(selfId);

    return SizedBox(
      width: size,
      height: size,
      child: CircleAvatar(
        backgroundColor: palette.line,
        child: chat.isDirect
            // substring rather than `.characters`: the latter needs
            // package:characters imported explicitly, and every name in this
            // audience is Cyrillic or Latin, so grapheme clusters are not the
            // risk here.
            ? Text(
                title.isEmpty ? '?' : title.substring(0, 1).toUpperCase(),
                style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600),
              )
            : Icon(
                chat.isChannel ? Icons.campaign_outlined : Icons.group_outlined,
                size: size * 0.5,
                color: palette.muted,
              ),
      ),
    );
  }
}
