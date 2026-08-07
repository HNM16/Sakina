import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../l10n.dart';
import '../models.dart';
import '../socket_client.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({
    super.key,
    required this.repository,
    required this.onSignOut,
  });

  final ChatRepository repository;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: l10n.t('sign_out'),
                onPressed: onSignOut,
              ),
            ],
          ),
          body: chats.isEmpty
              ? Center(child: Text(l10n.t('no_chats')))
              : ListView.separated(
                  itemCount: chats.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _ChatTile(
                    chat: chats[index],
                    selfId: repository.selfId,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(
                          repository: repository,
                          chatId: chats[index].id,
                        ),
                      ),
                    ),
                  ),
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showNewChatSheet(context),
            child: const Icon(Icons.edit),
          ),
        );
      },
    );
  }

  /// M0 has no contact discovery, so a chat is started by pasting a user id.
  /// Phone-book matching is an M1 problem and a privacy design of its own.
  void _showNewChatSheet(BuildContext context) {
    final controller = TextEditingController();
    final l10n = L10n.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.t('new_chat'), style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: l10n.t('peer_id_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(sheetContext);
                try {
                  await repository.api.createDirectChat(controller.text.trim());
                  await repository.bootstrap();
                  navigator.pop();
                } catch (_) {
                  navigator.pop();
                }
              },
              child: Text(l10n.t('continue')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.selfId, required this.onTap});

  final ChatSummary chat;
  final String selfId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = chat.displayTitle(selfId);
    final preview = chat.lastMessage?.text ?? '';

    return ListTile(
      leading: CircleAvatar(
        child: Text(title.isEmpty ? '?' : title.substring(0, 1).toUpperCase()),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: chat.unreadCount > 0
          ? Badge(label: Text('${chat.unreadCount}'))
          : null,
      onTap: onTap,
    );
  }
}
