import 'dart:async';

import 'package:flutter/foundation.dart';
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
      notifyListeners();
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
  List<ChatSummary> get chats => _chats;

  final Map<String, List<Message>> _messages = {};
  List<Message> messagesFor(String chatId) => _messages[chatId] ?? const [];

  final Map<String, DateTime> _typing = {};

  /// Load whatever the device already knows, before any network call. The chat
  /// list must be on screen at launch even with the radio off.
  Future<void> bootstrap() async {
    _chats = await store.loadChats();
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
        for (final chat in _chats) {
          _messages[chat.id] = await store.loadMessages(chat.id);
        }
        notifyListeners();

      case 'message':
        final message = Message.fromJson(Map<String, dynamic>.from(data as Map));
        await store.putMessage(message);
        await _refresh(message.chatId);

      case 'sent':
        final map = Map<String, dynamic>.from(data as Map);
        await store.markSent(
          map['client_id'] as String,
          id: map['id'] as String,
          seq: map['seq'] as int,
        );
        await _refresh(map['chat_id'] as String);

      case 'sync':
        final map = Map<String, dynamic>.from(data as Map);
        final messages = (map['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
        if (messages.isNotEmpty) {
          await store.putMessages(messages);
          await _refresh(map['chat_id'] as String);
        }
        // `has_more` means we fell too far behind to catch up inline; the rest
        // is fetched over HTTP rather than dragged through the socket.
        if (map['has_more'] == true) {
          unawaited(_backfill(map['chat_id'] as String));
        }

      case 'read':
        final map = Map<String, dynamic>.from(data as Map);
        await store.setReadCursor(map['chat_id'] as String, map['up_to_seq'] as int);
        _chats = await store.loadChats();
        notifyListeners();

      case 'typing':
        final map = Map<String, dynamic>.from(data as Map);
        _typing['${map['chat_id']}:${map['user_id']}'] = DateTime.now();
        notifyListeners();

      case 'error':
        final map = Map<String, dynamic>.from(data as Map);
        final ref = map['ref'] as String?;
        if (ref != null) {
          await store.markFailed(ref);
          notifyListeners();
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

  Future<void> _refresh(String chatId) async {
    _messages[chatId] = await store.loadMessages(chatId);
    _chats = await store.loadChats();
    notifyListeners();
  }

  /// Writes the message locally first and returns immediately — the bubble
  /// appears whether or not there is a connection. Delivery is the outbox's
  /// problem from here on.
  Future<void> sendText(String chatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final message = Message(
      clientId: _uuid.v4(),
      chatId: chatId,
      senderId: selfId,
      payload: {'type': 'text', 'text': trimmed},
      createdAt: DateTime.now(),
      state: MessageState.pending,
    );

    await store.putMessage(message);
    await _refresh(chatId);

    socket.send({
      't': 'send',
      'd': {
        'client_id': message.clientId,
        'chat_id': chatId,
        'payload': message.payload,
      },
    });
  }

  void markRead(String chatId, int upToSeq) {
    if (upToSeq <= 0) return;
    unawaited(store.setReadCursor(chatId, upToSeq));
    socket.send({
      't': 'read',
      'd': {'chat_id': chatId, 'up_to_seq': upToSeq},
    });
  }

  void notifyTyping(String chatId) {
    socket.send({
      't': 'typing',
      'd': {'chat_id': chatId},
    });
  }

  bool isTyping(String chatId) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 4));
    return _typing.entries
        .any((e) => e.key.startsWith('$chatId:') && e.value.isAfter(cutoff));
  }

  @override
  void dispose() {
    _frameSub.cancel();
    _stateSub.cancel();
    super.dispose();
  }
}
