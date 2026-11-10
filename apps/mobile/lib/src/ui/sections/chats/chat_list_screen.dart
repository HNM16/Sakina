import 'package:flutter/material.dart';

import '../../../chat_repository.dart';
import '../../../l10n.dart';
import '../../../layout.dart';
import '../../../media_service.dart';
import '../../../models.dart';
import '../../../motion.dart';
import '../../../socket_client.dart';
import '../../../theme.dart';
import 'chat_avatar.dart';
import 'chat_screen.dart';
import '../../chorkhona_refresh.dart';
import '../../indicators.dart';
import 'chat_sheets.dart';
import '../../skeletons.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({
    super.key,
    required this.repository,
    required this.media,
  });

  final ChatRepository repository;
  final MediaService media;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);

    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final chats = repository.chats;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.t('chats')),
            // Connection state belongs in the chrome, not in a blocking dialog:
            // the app stays fully usable offline, so a dropped socket is status,
            // not an error.
            bottom: repository.connection == SocketStatus.connected
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Container(
                      width: double.infinity,
                      // A quiet band, not a coloured alarm. Saffron is for
                      // rare warmth and pomegranate for loss (docs/BRAND.md);
                      // a dropped socket on a Tajik mobile network is neither,
                      // it is Tuesday. The text keeps full contrast because it
                      // is the part worth reading.
                      color: SakinaPalette.of(context).line,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        repository.connection == SocketStatus.connecting
                            ? l10n.t('connecting')
                            : l10n.t('offline'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
            // No actions: the language picker and sign-out moved to Profile
            // when the app grew a bottom bar. Settings in the chat list's app
            // bar is what an app does when it has nowhere else to put them.
          ),
          body: repository.loading
              // Not the empty state: an empty screen while SQLite opens reads
              // as "you have no chats", which is a different and much worse
              // message than "one moment".
              ? const ChatListSkeleton()
              : chats.isEmpty
              // An empty state with a next action, not a shrug. The first thing
              // a new user sees is this screen, and "no chats" alone tells them
              // nothing about what to do about it.
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: layout.gutter * 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ChorkhonaMark(size: 56),
                        SizedBox(height: layout.gap * 2),
                        Text(
                          l10n.t('no_chats'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        SizedBox(height: layout.gap * 2),
                        FilledButton(
                          onPressed: () => _newChat(context),
                          child: Text(l10n.t('new_chat')),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomScrollView(
                  // A sliver list rather than ListView.builder so the refresh
                  // control can sit above it — see ChorkhonaRefresh on why that
                  // API and not RefreshIndicator.
                  slivers: [
                    ChorkhonaRefresh(onRefresh: repository.resync),
                    SliverList.builder(
                      itemCount: chats.length,
                      addAutomaticKeepAlives: false,
                      // Space instead of dividers — brand rule 4. Fewer strokes
                      // is less to render and less to look at.
                      itemBuilder: (context, index) => EntranceFade(
                        // The stagger is keyed to the row's position, and the
                        // whole sequence finishes inside 220ms however many
                        // rows there are.
                        delay: SakinaMotion.staggerFor(context, index),
                        child: _ChatTile(
                          // The chat list reorders as messages arrive; a stable
                          // key lets Flutter move elements rather than rebuild
                          // them all — and it is what stops EntranceFade
                          // re-running its entrance on every incoming message.
                          key: ValueKey(chats[index].id),
                          chat: chats[index],
                          selfId: repository.selfId,
                          onTap: () => _openChat(context, chats[index].id),
                        ),
                      ),
                    ),
                    // Clears the FAB, so the last chat is not permanently half
                    // covered by it.
                    SliverToBoxAdapter(child: SizedBox(height: layout.gap * 6)),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _newChat(context),
            tooltip: l10n.t('new_chat'),
            child: const Icon(Icons.edit_outlined),
          ),
        );
      },
    );
  }

  void _openChat(BuildContext context, String chatId) {
    Navigator.of(context).push(
      SakinaPageRoute<void>(
        builder: (_) => ChatScreen(
          repository: repository,
          chatId: chatId,
          media: media,
        ),
      ),
    );
  }

  Future<void> _newChat(BuildContext context) async {
    final chat = await showNewChatSheet(
      context,
      api: repository.api,
      selfId: repository.selfId,
      onDirectChat: () => _askForPeerId(context),
    );
    if (chat == null) return;

    // The chat arrives over the socket as a `chat` frame too, but not for the
    // creator's own device on every path — a resync is cheap and makes the new
    // chat appear regardless of which got there first.
    await repository.resync();
    if (context.mounted) _openChat(context, chat.id);
  }

  /// Starting a direct chat by pasting a user id.
  ///
  /// This is the worst screen in the app and `docs/UX.md` says so: it is pure
  /// recall, which heuristic #6 exists to avoid. It survives only because
  /// contact discovery is an M1 feature with a privacy design of its own.
  Future<ChatSummary?> _askForPeerId(BuildContext context) async {
    final controller = TextEditingController();
    final l10n = L10n.of(context);

    final chat = await showDialog<ChatSummary>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('new_chat')),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: InputDecoration(hintText: l10n.t('peer_id_hint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              try {
                final created =
                    await repository.api.createDirectChat(controller.text.trim());
                navigator.pop(created);
              } catch (_) {
                navigator.pop();
              }
            },
            child: Text(l10n.t('continue')),
          ),
        ],
      ),
    );
    controller.dispose();
    return chat;
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    super.key,
    required this.chat,
    required this.selfId,
    required this.onTap,
  });

  final ChatSummary chat;
  final String selfId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);

    final title = chat.displayTitle(selfId, savedLabel: l10n.t('saved_messages'));
    // Not lastMessage.text: a photo has no text, and an empty subtitle reads as
    // a bug rather than as an attachment.
    final preview = chat.lastMessage?.previewText(l10n.t) ?? '';

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 4),
      minTileHeight: SakinaLayout.tapTarget + 8,
      // A1: the flight's other end is the conversation's app bar. Same widget
      // at both ends so nothing morphs mid-air.
      leading: Hero(
        tag: 'chat-avatar-${chat.id}',
        createRectTween: (begin, end) =>
            MaterialRectCenterArcTween(begin: begin, end: end),
        child: ChatAvatar(chat: chat, selfId: selfId, size: layout.avatarSize),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
      ),
      trailing: UnreadBadge(count: chat.unreadCount),
      onTap: onTap,
    );
  }
}
