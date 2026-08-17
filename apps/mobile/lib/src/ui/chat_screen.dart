import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../chat_repository.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';

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
    // Tells the repository which chat is on screen, so it only keeps this
    // chat's history in memory and loads it if this is the first open.
    unawaited(widget.repository.openChat(widget.chatId));
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    widget.repository.closeChat(widget.chatId);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markRead() {
    // The list is kept in seq order, so the highest seq is the last one that
    // has been acked. Folding over every message to rediscover that was O(n)
    // work on a hot path.
    final messages = widget.repository.messagesFor(widget.chatId);
    for (var i = messages.length - 1; i >= 0; i -= 1) {
      final seq = messages[i].seq;
      if (seq != null) {
        widget.repository.markRead(widget.chatId, seq);
        return;
      }
    }
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
                  // Keeping offscreen bubbles alive costs memory on a device
                  // that has little of it, and buys nothing — they are cheap to
                  // rebuild from a list already in memory.
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _Bubble(
                      // A stable key lets Flutter reuse elements when the list
                      // grows, instead of rebuilding every bubble because the
                      // indices shifted.
                      key: ValueKey(message.clientId),
                      message: message,
                      isMine: message.senderId == selfId,
                    );
                  },
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

/// Hoisted: `DateFormat` parses its pattern on construction, and building one
/// per bubble per rebuild was measurable work for a string that never changes.
final _timeFormat = DateFormat.Hm();

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final palette = SakinaPalette.of(context);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          // Named roles rather than Material containers: reading bubble colours
          // off the generated scheme means a seed change quietly restyles the
          // conversation.
          color: isMine ? palette.bubbleMine : palette.bubbleTheirs,
          borderRadius: BorderRadius.circular(16),
          border: isMine ? null : Border.all(color: palette.line),
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
                  _timeFormat.format(message.createdAt),
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
                    // Muted grey lands around 3:1 on the deep tile bubble —
                    // fine for a decorative glyph, not for the one pixel that
                    // tells you whether your message left the phone. It keeps
                    // the inherited text colour; only failure is coloured.
                    color: message.state == MessageState.failed ? palette.anor : null,
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
