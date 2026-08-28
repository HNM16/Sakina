import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../api_client.dart';
import '../chat_repository.dart';
import '../l10n.dart';
import '../layout.dart';
import '../media_service.dart';
import '../models.dart';
import '../motion.dart';
import '../theme.dart';
import 'chat_avatar.dart';
import 'chat_info_screen.dart';
import 'indicators.dart';
import 'media_bubble.dart';
import 'message_actions.dart';
import 'motion_primitives.dart';
import 'sheets.dart';
import 'skeletons.dart';
import 'swipe_to_reply.dart';

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
  final _uuid = const Uuid();

  /// Set while an attachment is on its way up. The composer is disabled for the
  /// duration: two uploads racing from one chat is a rare need and a common
  /// source of half-sent messages.
  bool _uploading = false;
  String? _uploadError;

  /// The message being replied to, from a swipe or the long-press menu.
  Message? _replyingTo;

  /// The client id of the message this screen just sent.
  ///
  /// A2 animates exactly one bubble — the one the user caused. Animating every
  /// newly-arrived message would mean the list jumps around whenever the other
  /// person is talking, which is motion nobody asked for.
  String? _justSent;

  /// How many messages were on screen at the last build, so an arrival can be
  /// told apart from a rebuild.
  int _lastCount = 0;

  /// True while a scroll-back page is being folded in. Growth from the *top*
  /// must not be mistaken for a new message arriving at the bottom.
  bool _loadingOlder = false;

  /// Whether the newest message should stay in view.
  ///
  /// True until the reader scrolls away from the bottom themselves, and true
  /// again when they come back. Deliberately *not* derived from the current
  /// offset on every frame: the socket's catch-up inserts older messages
  /// **above** the viewport, which moves the bottom away without the reader
  /// touching anything. Reading that as "they have scrolled up" is what left a
  /// 64-message chat opening at message 11.
  bool _pinnedToEnd = true;

  @override
  void initState() {
    super.initState();
    // Tells the repository which chat is on screen, so it only keeps this
    // chat's history in memory and loads it if this is the first open.
    unawaited(widget.repository.openChat(widget.chatId));
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  /// Near the top means the reader is asking for older messages.
  ///
  /// Cheap to call on every scroll frame: the repository returns immediately
  /// when a page is already in flight or the server has said there is no more.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    // Only a drag the reader made re-decides this. Programmatic jumps and
    // content arriving above them do not.
    if (position.userScrollDirection != ScrollDirection.idle) {
      _pinnedToEnd = position.maxScrollExtent - position.pixels < 160;
    }

    if (position.pixels <= 160) unawaited(_loadOlder());
  }

  Future<void> _loadOlder() async {
    final repository = widget.repository;
    if (_loadingOlder ||
        repository.historyLoading(widget.chatId) ||
        !repository.hasMoreHistory(widget.chatId) ||
        !_scrollController.hasClients) {
      return;
    }

    _loadingOlder = true;
    final extentBefore = _scrollController.position.maxScrollExtent;
    final offsetBefore = _scrollController.position.pixels;

    try {
      await repository.loadOlderMessages(widget.chatId);
    } finally {
      _keepPlaceAfterOlderPage(extentBefore, offsetBefore);
    }
  }

  /// Puts the reader back where they were after a page lands above them.
  ///
  /// Separate from [_loadOlder] only so that method's `finally` contains a
  /// call and not a `return` — control flow in a finally clause swallows
  /// whatever the try was throwing.
  void _keepPlaceAfterOlderPage(double extentBefore, double offsetBefore) {
    if (!mounted) {
      _loadingOlder = false;
      return;
    }
    // The conversation grew *above* them, so holding the same pixel offset
    // would throw them backwards through the history they just asked for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        final grew = _scrollController.position.maxScrollExtent - extentBefore;
        if (grew > 0) _scrollController.jumpTo(offsetBefore + grew);
      }
      _loadingOlder = false;
    });
  }

  /// Keeps the newest message in view.
  ///
  /// A chat opens at the bottom, because the last thing said is the thing you
  /// came to read — and history arrives after the first paint, so this has to
  /// run when the list grows rather than once on init. It only follows a
  /// reader who was already at the bottom: yanking someone back down while
  /// they are reading upwards is the single rudest thing a message list can
  /// do.
  void _stickToEnd(int count) {
    if (count <= _lastCount) {
      _lastCount = count;
      return;
    }
    _lastCount = count;
    if (_loadingOlder || !_pinnedToEnd) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.repository.closeChat(widget.chatId);
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
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
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final replyTo = _replyingTo?.seq;
    _controller.clear();
    setState(() => _replyingTo = null);

    // The lightest tick available. This fires fifty times an evening, and
    // anything heavier becomes fatigue rather than confirmation.
    SakinaHaptics.sent(context);

    // Generated here and marked before the send, so the bubble is animating the
    // first time it is ever built.
    final clientId = _uuid.v4();
    setState(() => _justSent = clientId);

    await widget.repository.sendPayload(
      widget.chatId,
      {
        'type': 'text',
        'text': text,
        if (replyTo != null) 'reply_to_seq': replyTo,
      },
      clientId: clientId,
    );

    // Cleared once it has played. Without this the marker sticks, and scrolling
    // the message off screen and back re-creates the widget — which would run
    // the entrance again, weeks later, for no reason.
    Future<void>.delayed(SakinaMotion.travel, () {
      if (mounted && _justSent == clientId) setState(() => _justSent = null);
    });

    await _scrollToEnd();
  }

  void _startReply(Message message) {
    setState(() => _replyingTo = message);
  }

  /// Who wrote a message, for a quote or a reply preview.
  String _authorOf(Message message, L10n l10n, ChatSummary? chat) {
    if (message.senderId == widget.repository.selfId) return l10n.t('you');
    for (final member in chat?.members ?? const <PublicUser>[]) {
      if (member.id == message.senderId) return member.displayName;
    }
    // A member who has left, or one outside the preview slice a channel sends.
    // A neutral person, not "message unavailable" — the message is right here.
    return l10n.t('someone');
  }

  /// Messages by seq, so resolving a quote is a lookup.
  ///
  /// Built once per build rather than scanned per bubble. The scan version was
  /// O(n²) across the list — on a chat with a few hundred messages that is
  /// hundreds of thousands of comparisons every frame the list rebuilds, which
  /// is exactly the kind of thing docs/PERFORMANCE.md exists to keep out.
  Map<int, Message> _indexBySeq(List<Message> messages) {
    final index = <int, Message>{};
    for (final message in messages) {
      final seq = message.seq;
      if (seq != null) index[seq] = message;
    }
    return index;
  }

  /// Guardrail G2: motion needs a path that removes it rather than one that
  /// shortens it. [SakinaMotion.duration] returns Duration.zero under
  /// reduce-motion, and animateTo with a zero duration jumps rather than eases.
  Future<void> _scrollToEnd() async {
    if (!_scrollController.hasClients) return;
    if (!mounted) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: SakinaMotion.duration(context, SakinaMotion.travel),
      curve: SakinaMotion.curve(context),
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
      if (!mounted) return;
      SakinaHaptics.failed(context);
      setState(() => _uploadError = err.message);
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
        // Scheduled from build rather than a callback because the list grows
        // for three different reasons — cache read, history page, socket
        // frame — and this is the one place all three are visible.
        _stickToEnd(messages.length);
        // Only while paging backwards. On the very first load the cached
        // conversation is already on screen, and a spinner above it would say
        // "nothing here yet" about content the reader can see.
        final loadingOlder =
            widget.repository.historyLoading(widget.chatId) && messages.isNotEmpty;
        // Only built when something in this chat actually quotes something.
        final bySeq = messages.any((m) => m.replyToSeq != null)
            ? _indexBySeq(messages)
            : const <int, Message>{};

        return Scaffold(
          appBar: AppBar(
            // The way back is a button in the corner as well as a gesture,
            // because a gesture nobody has discovered yet is not a way back.
            //
            // Explicit rather than the AppBar's automatic one, which reads its
            // tooltip from MaterialLocalizations — and Flutter ships no Tajik,
            // so a Tajik phone would be told "Назад" (see the delegates in
            // l10n.dart). This is the one string on the screen that our own
            // table can fix.
            leading: IconButton(
              icon: const BackButtonIcon(),
              tooltip: l10n.t('back'),
              onPressed: () => Navigator.maybePop(context),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                // A1: the same tag the list row uses, so Flutter flies the
                // avatar between the two screens instead of cross-fading whole
                // pages. It answers "where did I come from" without a thought,
                // which is most of what makes a messenger feel expensive.
                if (chat != null)
                  Hero(
                    tag: 'chat-avatar-${chat.id}',
                    // The default flight wraps the child in a Material of the
                    // wrong shape mid-flight; a circle keeps it a circle the
                    // whole way across.
                    createRectTween: (begin, end) =>
                        MaterialRectCenterArcTween(begin: begin, end: end),
                    child: ChatAvatar(chat: chat, selfId: selfId, size: 34),
                  ),
                SizedBox(width: layout.gap * 0.8),
                Expanded(
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat?.displayTitle(selfId, savedLabel: l10n.t('saved_messages')) ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (typing)
                  // A5: movement is the whole information content — text reads
                  // as a status bar, dots read as a person.
                  Row(
                    children: [
                      Text(
                        l10n.t('typing'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: palette.muted),
                      ),
                      SizedBox(width: layout.gap * 0.4),
                      const TypingDots(),
                    ],
                  )
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
                    SakinaPageRoute<void>(
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
                child: messages.isEmpty && widget.repository.loading
                    ? const MessageListSkeleton()
                    : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length + (loadingOlder ? 1 : 0),
                  // Keeping offscreen bubbles alive costs memory on a device
                  // that has little of it, and buys nothing — they are cheap to
                  // rebuild from a list already in memory.
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (context, rawIndex) {
                    if (loadingOlder && rawIndex == 0) {
                      return const _OlderHistoryLoading();
                    }
                    final index = loadingOlder ? rawIndex - 1 : rawIndex;
                    final message = messages[index];
                    final isMine = message.senderId == selfId;
                    final replyTo = message.replyToSeq;
                    final quoted = replyTo == null ? null : bySeq[replyTo];

                    // The two primitives that belong on a message, in the
                    // order their meanings compose: it breathes while in doubt,
                    // and light crosses it at the moment the doubt ends.
                    final bubble = _Bubble(
                      message: message,
                      isMine: isMine,
                      media: widget.media,
                      quotedAuthor:
                          quoted == null ? null : _authorOf(quoted, l10n, chat),
                      quotedPreview: quoted?.previewText(l10n.t),
                      // A reply pointing at something not in the loaded window
                      // still renders — it says the target is unavailable
                      // rather than dropping the reply.
                      quoteMissing: replyTo != null && quoted == null,
                    );

                    // A7/A8. Both gestures are disabled where they would lead
                    // to a composer the user does not have.
                    final canReply = chat?.canPost ?? true;

                    return KeyedSubtree(
                      // A stable key lets Flutter reuse elements when the list
                      // grows, instead of rebuilding every bubble because the
                      // indices shifted.
                      key: ValueKey(message.clientId),
                      child: _MaybeSendEntrance(
                        // A2: only the bubble this screen just created.
                        animate: message.clientId == _justSent,
                        child: SwipeToReply(
                          enabled: canReply && message.type != 'system',
                          onReply: () => _startReply(message),
                          // Innermost, so the menu lifts the bubble itself
                          // rather than the gesture wrapper with its reply
                          // arrow baked in.
                          child: LongPressActions(
                            canReply: canReply,
                            onReply: () => _startReply(message),
                            copyText: message.type == 'text'
                                ? message.text
                                : message.caption,
                            child: Breathing(
                              // НАФАС. Only ours — somebody else's message is
                              // not in doubt from where we are standing.
                              waiting:
                                  isMine && message.state == MessageState.pending,
                              child: LightPass(
                                // ТОБ. The trigger is the delivery state, so
                                // the pass runs at the instant pending becomes
                                // sent and at no other time.
                                trigger: message.state,
                                enabled: isMine,
                                child: bubble,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                        // A7: what the swipe armed, and the way out of it.
                        // Arming a reply by accident is the likeliest failure
                        // of the gesture, so dismissing has to be one tap.
                        if (_replyingTo != null)
                          ReplyPreview(
                            author: _authorOf(_replyingTo!, l10n, chat),
                            preview: _replyingTo!.previewText(l10n.t),
                            onCancel: () => setState(() => _replyingTo = null),
                          ),
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

/// The strip at the top of the list while an older page is being fetched.
///
/// НАФАС, not a spinner: the vocabulary in docs/MOTION.md says the object in
/// doubt expresses its own state, and what is in doubt here is whether there is
/// more conversation above this line.
class _OlderHistoryLoading extends StatelessWidget {
  const _OlderHistoryLoading();

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: layout.gap),
      child: Center(
        child: Breathing(
          waiting: true,
          child: Text(
            L10n.of(context).t('loading'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
      ),
    );
  }
}

/// Runs the A2 entrance for exactly one bubble.
///
/// A plain `if` around [EntranceFade] would swap the widget type once the
/// animation is no longer wanted, which rebuilds the subtree and loses any
/// gesture in progress. Keeping the wrapper constant and switching its
/// behaviour avoids that.
class _MaybeSendEntrance extends StatelessWidget {
  const _MaybeSendEntrance({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return EntranceFade(
      // Rises further and grows slightly, so it reads as lifting out of the
      // composer rather than sliding in from off-screen.
      offset: 0.45,
      scaleFrom: 0.94,
      duration: SakinaMotion.travel,
      child: child,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.media,
    this.quotedAuthor,
    this.quotedPreview,
    this.quoteMissing = false,
  });

  final Message message;
  final bool isMine;
  final MediaService media;
  final String? quotedAuthor;
  final String? quotedPreview;
  final bool quoteMissing;

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
            if (quotedAuthor != null)
              QuotedMessage(
                author: quotedAuthor!,
                preview: quotedPreview ?? '',
              )
            else if (quoteMissing)
              QuotedMessage(
                author: L10n.of(context).t('message_unavailable'),
                preview: '',
              ),
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
