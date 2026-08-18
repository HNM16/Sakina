import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../chat_repository.dart';
import '../l10n.dart';
import '../layout.dart';
import '../media_service.dart';
import '../models.dart';
import '../theme.dart';
import 'chat_info_screen.dart';
import 'media_bubble.dart';
import 'sheets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.repository,
    required this.chatId,
    required this.media,
  });

  final ChatRepository repository;
  final String chatId;
  final MediaService media;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// Set while an attachment is on its way up. The composer is disabled for the
  /// duration: two uploads racing from one chat is a rare need and a common
  /// source of half-sent messages.
  bool _uploading = false;
  String? _uploadError;

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

    await _scrollToEnd();
  }

  /// Guardrail G2: motion needs a path that removes it rather than one that
  /// shortens it. [SakinaLayout.motion] returns Duration.zero when the platform
  /// asks for reduced motion, and animateTo with a zero duration jumps.
  Future<void> _scrollToEnd() async {
    if (!_scrollController.hasClients) return;
    if (!mounted) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: SakinaLayout.of(context).motion(),
      curve: SakinaTheme.motionCurve,
    );
  }

  Future<void> _attach() async {
    final choice = await showAttachSheet(context);
    if (choice == null || !mounted) return;

    setState(() => _uploadError = null);

    try {
      final picked = switch (choice) {
        AttachChoice.camera => await widget.media.pickImage(fromCamera: true),
        AttachChoice.photo => await widget.media.pickImage(fromCamera: false),
        AttachChoice.video => await widget.media.pickVideo(fromCamera: false),
        AttachChoice.file => await widget.media.pickFile(),
      };
      if (picked == null || !mounted) return;

      // Only above the threshold. Asking about every 200KB photo trains the
      // dialog away inside a week, which is how confirmation dialogs die.
      if (picked.isLarge) {
        final proceed = await confirmLargeUpload(context, humanSize: picked.humanSize);
        if (!proceed || !mounted) return;
      }

      setState(() => _uploading = true);
      final caption = _controller.text.trim();
      final payload = await widget.media.upload(
        chatId: widget.chatId,
        media: picked,
        caption: caption,
      );
      _controller.clear();
      await widget.repository.sendPayload(widget.chatId, payload);
      await _scrollToEnd();
    } on ApiException catch (err) {
      if (mounted) setState(() => _uploadError = err.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
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
                Text(
                  chat?.displayTitle(selfId, savedLabel: l10n.t('saved_messages')) ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (typing)
                  Text(l10n.t('typing'), style: Theme.of(context).textTheme.bodySmall)
                else if (chat != null && !chat.isDirect)
                  Text(
                    '${chat.memberCount} '
                    '${l10n.t(chat.isChannel ? 'subscribers' : 'members').toLowerCase()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
              ],
            ),
            actions: [
              // A direct chat has no membership to manage; offering the screen
              // and then showing two names would be a dead end.
              if (chat != null && !chat.isDirect)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: l10n.t(chat.isChannel ? 'subscribers' : 'members'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatInfoScreen(
                        repository: widget.repository,
                        chatId: widget.chatId,
                      ),
                    ),
                  ),
                ),
            ],
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
                      media: widget.media,
                    );
                  },
                ),
              ),
              // A channel subscriber gets no composer at all, rather than one
              // that rejects them. The server is still the enforcement — see
              // insertMessage — so this being wrong costs a confusing error,
              // not a leak.
              if (chat != null && !chat.canPost)
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.gutter,
                      vertical: layout.gap,
                    ),
                    child: Text(
                      l10n.t('read_only_channel'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.muted),
                    ),
                  ),
                )
              else
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_uploadError != null)
                          Padding(
                            padding: EdgeInsets.only(bottom: layout.gap / 2),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, size: 16, color: palette.anor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _uploadError!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: palette.anor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _uploading ? null : _attach,
                              tooltip: l10n.t('attach'),
                              constraints: const BoxConstraints(
                                minWidth: SakinaLayout.tapTarget,
                                minHeight: SakinaLayout.tapTarget,
                              ),
                              icon: const Icon(Icons.attach_file),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                enabled: !_uploading,
                                textInputAction: TextInputAction.send,
                                // Long messages are normal; a single line that
                                // scrolls sideways is not.
                                minLines: 1,
                                maxLines: 4,
                                onChanged: (_) =>
                                    widget.repository.notifyTyping(widget.chatId),
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(
                                  hintText: _uploading
                                      ? l10n.t('uploading')
                                      : l10n.t('message_hint'),
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _uploading ? null : _send,
                              tooltip: l10n.t('send'),
                              constraints: const BoxConstraints(
                                minWidth: SakinaLayout.tapTarget,
                                minHeight: SakinaLayout.tapTarget,
                              ),
                              icon: _uploading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
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
  const _Bubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.media,
  });

  final Message message;
  final bool isMine;
  final MediaService media;

  @override
  Widget build(BuildContext context) {
    final palette = SakinaPalette.of(context);
    final layout = SakinaLayout.of(context);

    // A service message is about the chat, not from a person. Centred, quiet,
    // and never in a bubble — it is not somebody talking.
    if (message.type == 'system') {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.gap / 2),
        child: Text(
          _systemText(context, message),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
        ),
      );
    }

    final caption = message.caption;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          // The fraction goes up on a narrow screen — see the note on
          // SakinaLayout.bubbleMaxWidth. Measured against the pane, not the
          // window, so a tablet's two-pane layout does not get phone-sized
          // bubbles in a 600-unit column.
          maxWidth: layout.bubbleMaxWidth(layout.detailPaneWidth - layout.gutter * 2),
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
            if (message.isMedia) ...[
              MediaAttachment(message: message, media: media),
              if (caption != null && caption.isNotEmpty) ...[
                SizedBox(height: layout.gap / 2),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(caption),
                ),
              ],
            ] else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(message.text),
              ),
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

/// Service messages, rendered from their event rather than from server-authored
/// prose — so they arrive in the reader's language, not the sender's.
String _systemText(BuildContext context, Message message) {
  final l10n = L10n.of(context);
  final event = message.payload['event'] as String?;
  return switch (event) {
    'chat_created' => (message.payload['meta'] as Map?)?['title'] as String? ??
        l10n.t('system_event'),
    'member_added' => l10n.t('add_people'),
    'member_removed' => l10n.t('left_chat'),
    'title_changed' => (message.payload['meta'] as Map?)?['title'] as String? ??
        l10n.t('system_event'),
    _ => l10n.t('system_event'),
  };
}
