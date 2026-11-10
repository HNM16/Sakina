import 'package:flutter/material.dart';

import '../section.dart';
import 'chat_list_screen.dart';

/// Conversations. The section the app is for.
class ChatsSection extends SakinaSection {
  const ChatsSection();

  @override
  String get id => 'chats';

  @override
  String get labelKey => 'chats';

  @override
  IconData get icon => Icons.chat_bubble_outline;

  @override
  IconData get selectedIcon => Icons.chat_bubble;

  @override
  Widget build(BuildContext context, SectionScope scope) => ChatListScreen(
        repository: scope.repository,
        media: scope.media,
      );
}
