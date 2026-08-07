import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../chat_repository.dart';
import '../l10n.dart';
import '../models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.repository, required this.chatId});

  final ChatRepository repository;
  final String chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markRead() {
    final messages = widget.repository.messagesFor(widget.chatId);
    final highest = messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    widget.repository.markRead(widget.chatId, highest);
  }

  Future<void> _send() async {
    final text = _controller.text;
    _controller.clear();
    await widget.repository.sendText(widget.chatId, text);

    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final selfId = widget.repository.selfId;

    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final matching =
            widget.repository.chats.where((c) => c.id == widget.chatId).toList();
        final chat = matching.isEmpty ? null : matching.first;
        final messages = widget.repository.messagesFor(widget.chatId);
        final typing = widget.repository.isTyping(widget.chatId);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat?.displayTitle(selfId) ?? ''),
                if (typing)
                  Text(l10n.t('typing'), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _Bubble(
                    message: messages[index],
                    isMine: messages[index].senderId == selfId,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          onChanged: (_) => widget.repository.notifyTyping(widget.chatId),
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: l10n.t('message_hint'),
                            border: const OutlineInputBorder(),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(message.text),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.Hm().format(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  // The delivery state the whole protocol exists to make
                  // trustworthy: a clock until the server assigns a seq.
                  Icon(
                    switch (message.state) {
                      MessageState.pending => Icons.schedule,
                      MessageState.sent => Icons.done,
                      MessageState.failed => Icons.error_outline,
                    },
                    size: 14,
                    color: message.state == MessageState.failed ? scheme.error : null,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
