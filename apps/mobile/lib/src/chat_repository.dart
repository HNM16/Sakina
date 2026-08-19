import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';
import 'socket_client.dart';

/// Sits between the socket and the UI, and owns the one rule that makes this
/// app work on a bad network: **nothing reaches a widget except through
/// [LocalStore]**. Frames arrive, get written to SQLite, and only then does the
/// UI get told to re-read. A dropped connection therefore changes nothing about
/// what is on screen.
class ChatRepository extends ChangeNotifier {
  ChatRepository({
    required this.api,
    required this.store,
    required this.socket,
    required this.selfId,
  }) {
    _frameSub = socket.frames.listen(_onFrame);
    _stateSub = socket.connectionState.listen((state) {
      _connection = state;
      if (state == SocketStatus.connected) {
        unawaited(_onConnected());
      }
      if (!_disposed) notifyListeners();
    });
  }

  final ApiClient api;
  final LocalStore store;
  final SocketClient socket;
  final String selfId;

  static const _uuid = Uuid();

  late final StreamSubscription<Map<String, dynamic>> _frameSub;
  late final StreamSubscription<SocketStatus> _stateSub;

  SocketStatus _connection = SocketStatus.disconnected;
  SocketStatus get connection => _connection;

  List<ChatSummary> _chats = [];

  /// True until the first read off local disk finishes.
  ///
  /// Distinguishes "we do not know yet" from "there is nothing", which are the
  /// same picture and completely different sentences. Without it a cold start
  /// shows the empty state — "no chats yet, start one" — to somebody who has
  /// fifty, for as long as SQLite takes to open.
  bool _loading = true;
  bool get loading => _loading;
  List<ChatSummary> get chats => _chats;

  final Map<String, List<Message>> _messages = {};
  List<Message> messagesFor(String chatId) => _messages[chatId] ?? const [];

  /// Which chat is on screen. Lets the repository avoid loading history for
  /// chats nobody is looking at.
  String? _activeChatId;

  /// Called when a chat screen opens. Loads its history if it is not in memory.
  Future<void> openChat(String chatId) async {
    _activeChatId = chatId;
    if (!_messages.containsKey(chatId)) {
      _messages[chatId] = await store.loadMessages(chatId);
      if (_disposed) return;
      notifyListeners();
    }
  }

  void closeChat(String chatId) {
    if (_activeChatId == chatId) _activeChatId = null;
  }

  final Map<String, DateTime> _typing = {};

  /// How long a typing indicator stays up after the last frame.
  static const _typingWindow = Duration(seconds: 4);

  /// Last time we told the server *we* were typing, so keystrokes do not each
  /// become a socket frame.
  DateTime? _lastTypingSent;

  /// Load whatever the device already knows, before any network call. The chat
  /// list must be on screen at launch even with the radio off.
  Future<void> bootstrap() async {
    try {
      _chats = await store.loadChats();
    } finally {
      // In the finally block: a failed read still has to leave the loading
      // state, or a skeleton shimmers forever and the user cannot even reach
      // the empty state's "start a chat" button.
      _loading = false;
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _onConnected() async {
    // Tell the server where we got to in every chat; it replies with the diff.
    final cursors = await store.syncCursors();
    final known = {for (final chat in _chats) chat.id};
    for (final chatId in known) {
      cursors.putIfAbsent(chatId, () => 0);
    }

    if (cursors.isNotEmpty) {
      socket.send({
        't': 'sync',
        'd': {
          'cursors': [
            for (final entry in cursors.entries)
              {'chat_id': entry.key, 'last_seq': entry.value},
          ],
        },
      });
    }

    await _flushOutbox();
  }

  /// Called when a push says something changed.
  ///
  /// The push carries a chat id and a seq, never message text, so the content
  /// still has to be fetched. If the socket is up this is a cheap sync frame;
  /// if it is not, opening it triggers the same catch-up anyway.
  Future<void> resync() async {
    if (socket.current == SocketStatus.connected) {
      await _onConnected();
    }
    // Otherwise the socket is already reconnecting on its own backoff, and
    // `_onConnected` will fire when it lands. Nothing to force.
  }

  /// Re-sends everything composed but never acked. Same client_id as the first
  /// attempt, so the server recognises the retry and does not duplicate it.
  Future<void> _flushOutbox() async {
    for (final message in await store.pendingMessages()) {
      socket.send({
        't': 'send',
        'd': {
          'client_id': message.clientId,
          'chat_id': message.chatId,
          'payload': message.payload,
        },
      });
    }
  }

  Future<void> _onFrame(Map<String, dynamic> frame) async {
    final data = frame['d'];

    switch (frame['t'] as String) {
      case 'ready':
        final map = Map<String, dynamic>.from(data as Map);
        final chats = (map['chats'] as List<dynamic>)
            .map((c) => ChatSummary.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
        await store.upsertChats(chats);
        _chats = await store.loadChats();
        // Only the chat actually on screen needs its history in memory at
        // connect time; the rest load when opened. Eagerly decoding every
        // message of every chat was multiplying startup cost by chat count.
        for (final chat in _chats) {
          if (_messages.containsKey(chat.id) || chat.id == _activeChatId) {
            _messages[chat.id] = await store.loadMessages(chat.id);
          }
        }
        if (_disposed) return;
        notifyListeners();

      // Someone added you to a group, renamed it, or promoted you.
      //
      // Without this frame the chat only appears at the next reconnect, and a
      // phone stays connected for hours — so being added to a group would look
      // like nothing happening at all.
      case 'chat':
        final chat = ChatSummary.fromJson(Map<String, dynamic>.from(data as Map));
        await store.upsertChats([chat]);
        _chats = await store.loadChats();
        if (_disposed) return;
        notifyListeners();

      // Removed, or you left from another device.
      case 'chat_removed':
        final chatId = (Map<String, dynamic>.from(data as Map))['chat_id'] as String;
        await store.removeChat(chatId);
        _messages.remove(chatId);
        _chats = await store.loadChats();
        if (_disposed) return;
        notifyListeners();

      case 'message':
        final message = Message.fromJson(Map<String, dynamic>.from(data as Map));
        await store.putMessage(message);
        _applyMessage(message);

      case 'sent':
        final map = Map<String, dynamic>.from(data as Map);
        final clientId = map['client_id'] as String;
        final chatId = map['chat_id'] as String;
        await store.markSent(clientId, id: map['id'] as String, seq: map['seq'] as int);

        // Flip the one bubble from clock to tick. Re-reading the chat to learn
        // something we already know would cost a hundred row decodes.
        final list = _messages[chatId];
        final index = list?.indexWhere((m) => m.clientId == clientId) ?? -1;
        if (list != null && index != -1) {
          list[index] = list[index].copyWith(
            id: map['id'] as String,
            seq: map['seq'] as int,
            state: MessageState.sent,
          );
          _chatListDirty = true;
          _scheduleNotify();
        } else {
          await _refresh(chatId);
        }

      case 'sync':
        final map = Map<String, dynamic>.from(data as Map);
        final messages = (map['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
        if (messages.isNotEmpty) {
          await store.putMessages(messages);
          // One scheduled rebuild for the whole page, not one per message.
          for (final message in messages) {
            _applyMessage(message);
          }
        }
        // `has_more` means we fell too far behind to catch up inline; the rest
        // is fetched over HTTP rather than dragged through the socket.
        if (map['has_more'] == true) {
          unawaited(_backfill(map['chat_id'] as String));
        }

      case 'read':
        final map = Map<String, dynamic>.from(data as Map);
        await store.setReadCursor(map['chat_id'] as String, map['up_to_seq'] as int);
        _chatListDirty = true;
        _scheduleNotify();

      case 'typing':
        final map = Map<String, dynamic>.from(data as Map);
        final key = '${map['chat_id']}:${map['user_id']}';
        final wasTyping = _typing[key] != null &&
            DateTime.now().difference(_typing[key]!) < _typingWindow;
        _typing[key] = DateTime.now();
        // Typing frames arrive several times a second per participant. Only the
        // transition from "not typing" to "typing" changes anything on screen;
        // the repeats are keepalives and must not rebuild the message list.
        if (!wasTyping) _scheduleNotify();

      case 'error':
        final map = Map<String, dynamic>.from(data as Map);
        final ref = map['ref'] as String?;
        if (ref != null) {
          await store.markFailed(ref);
          for (final entry in _messages.entries) {
            final index = entry.value.indexWhere((m) => m.clientId == ref);
            if (index != -1) {
              entry.value[index] = entry.value[index].copyWith(state: MessageState.failed);
              break;
            }
          }
          _scheduleNotify();
        }
        debugPrint('socket error: ${map['code']} ${map['message']}');
    }
  }

  Future<void> _backfill(String chatId) async {
    try {
      final page = await api.history(chatId, limit: 100);
      await store.putMessages(page.messages);
      await _refresh(chatId);
    } catch (err) {
      debugPrint('backfill failed for $chatId: $err');
    }
  }

  /// Full reload of one chat. Correct but expensive — prefer [_applyMessage].
  Future<void> _refresh(String chatId) async {
    _messages[chatId] = await store.loadMessages(chatId);
    _chats = await store.loadChats();
    _scheduleNotify();
  }

  /// The hot path: one message arrived, so update one message.
  ///
  /// The previous version re-read the whole chat (up to a hundred rows, each
  /// re-decoded from JSON) *and* the whole chat list on every single incoming
  /// message, all on the UI isolate. A burst of twenty messages meant twenty
  /// full reloads and twenty whole-tree rebuilds, nineteen of which were thrown
  /// away before anything was painted.
  ///
  /// Now the in-memory list is patched in place and the chat list is refreshed
  /// once per frame.
  /// Sort key for a message that has not been acked yet.
  ///
  /// Mirrors `COALESCE(seq, 9223372036854775807)` in [LocalStore], so the order
  /// held in memory is the same one the database would return. Pending messages
  /// belong at the end: they were composed after everything the server has
  /// acked, and they slot into place once their seq arrives.
  static const _pendingSortKey = 9223372036854775807;

  void _applyMessage(Message message) {
    final list = _messages[message.chatId] ??= <Message>[];
    final existing = list.indexWhere((m) => m.clientId == message.clientId);

    if (existing != -1) {
      list[existing] = message;
    } else {
      // seq is gapless and monotonic, so an arriving message almost always
      // belongs at the end — but not always *the* end, because unsent messages
      // sit there waiting for their ack. Scanning back from the end is O(1) for
      // the common case and still puts a newly acked message ahead of anything
      // still pending, which a blind append would get wrong.
      final key = message.seq ?? _pendingSortKey;
      var index = list.length;
      while (index > 0 && (list[index - 1].seq ?? _pendingSortKey) > key) {
        index -= 1;
      }
      list.insert(index, message);
    }

    _chatListDirty = true;
    _scheduleNotify();
  }

  /// Coalesce rebuilds to at most one per frame.
  ///
  /// `notifyListeners` rebuilds everything under an `AnimatedBuilder`, so
  /// calling it once per socket frame is the difference between a smooth list
  /// and a stuttering one.
  ///
  /// This waits for the next frame rather than a microtask, and the distinction
  /// matters: every WebSocket frame arrives in its own event-loop turn, so
  /// microtask batching would still produce one rebuild per message and achieve
  /// nothing. Deferring to the frame is what actually collapses a burst of
  /// twenty messages into one rebuild.
  bool _notifyScheduled = false;
  bool _chatListDirty = false;
  bool _disposed = false;

  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _notifyScheduled = false;
      if (_disposed) return;

      if (_chatListDirty) {
        _chatListDirty = false;
        // One query now, rather than one per chat — see LocalStore.loadChats.
        _chats = await store.loadChats();
        // The await gives the widget tree a chance to be torn down underneath
        // us; notifying a disposed ChangeNotifier throws.
        if (_disposed) return;
      }

      notifyListeners();
    });

    // `addPostFrameCallback` only runs if a frame is actually scheduled, and an
    // idle app schedules none. Without this, a message arriving while nothing
    // is animating would never be shown.
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Writes the message locally first and returns immediately — the bubble
  /// appears whether or not there is a connection. Delivery is the outbox's
  /// problem from here on.
  Future<String?> sendText(String chatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return sendPayload(chatId, {'type': 'text', 'text': trimmed});
  }

  /// Send any message payload — text, an attachment, and eventually a payment.
  ///
  /// Everything goes through here so that the optimistic-render-then-ack path
  /// is written once. Adding a message type must never mean adding a second
  /// send path, which is the whole premise of the open `type` enum in
  /// docs/PROTOCOL.md.
  ///
  /// For an attachment the bytes are already in storage by the time this is
  /// called — the payload carries the key, not the file — so a media message
  /// travels the same size as a text one and retries just as cheaply.
  /// Returns the `client_id` the message was stored under.
  ///
  /// [clientId] can be supplied by the caller so it knows the id *before* the
  /// message exists. The send animation needs that: setting the flag after
  /// awaiting would mean the bubble renders once plainly, then re-renders
  /// animating from zero opacity, which is a visible flash rather than an
  /// entrance.
  Future<String> sendPayload(
    String chatId,
    Map<String, dynamic> payload, {
    String? clientId,
  }) async {
    final message = Message(
      clientId: clientId ?? _uuid.v4(),
      chatId: chatId,
      senderId: selfId,
      payload: payload,
      createdAt: DateTime.now(),
      state: MessageState.pending,
    );

    await store.putMessage(message);
    _applyMessage(message);

    socket.send({
      't': 'send',
      'd': {
        'client_id': message.clientId,
        'chat_id': chatId,
        'payload': message.payload,
      },
    });

    return message.clientId;
  }

  void markRead(String chatId, int upToSeq) {
    if (upToSeq <= 0) return;
    unawaited(store.setReadCursor(chatId, upToSeq));
    socket.send({
      't': 'read',
      'd': {'chat_id': chatId, 'up_to_seq': upToSeq},
    });
  }

  /// Throttled hard. This is called from `onChanged`, so without a throttle
  /// every keystroke became a WebSocket frame — a burst of traffic on metered
  /// mobile data, and a rebuild on the recipient for each one.
  void notifyTyping(String chatId) {
    final now = DateTime.now();
    if (_lastTypingSent != null && now.difference(_lastTypingSent!) < const Duration(seconds: 3)) {
      return;
    }
    _lastTypingSent = now;
    socket.send({
      't': 'typing',
      'd': {'chat_id': chatId},
    });
  }

  bool isTyping(String chatId) {
    final cutoff = DateTime.now().subtract(_typingWindow);
    for (final entry in _typing.entries) {
      if (entry.value.isAfter(cutoff) && entry.key.startsWith('$chatId:')) return true;
    }
    return false;
  }

  @override
  void dispose() {
    // Set before cancelling: a frame callback already queued will check this
    // and bail rather than notifying a disposed ChangeNotifier, which throws.
    _disposed = true;
    _frameSub.cancel();
    _stateSub.cancel();
    super.dispose();
  }
}
