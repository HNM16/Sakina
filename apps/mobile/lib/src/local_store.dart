import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The device's copy of the world.
///
/// The rule this file exists to enforce: **the UI reads only from here.** The
/// network layer's entire job is to write into this database; widgets never
/// render a network response directly. That is what makes the app instant on a
/// slow link and usable with no link at all — and it is a discipline that has to
/// hold from the first screen, because it cannot be introduced later.
class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  static Future<LocalStore> open() async {
    final path = p.join(await getDatabasesPath(), 'sakina.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            title TEXT,
            last_seq INTEGER NOT NULL DEFAULT 0,
            read_up_to_seq INTEGER NOT NULL DEFAULT 0,
            members_json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            client_id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            id TEXT,
            seq INTEGER,
            state TEXT NOT NULL DEFAULT 'sent'
          )
        ''');
        // client_id as the primary key mirrors the server's uniqueness rule, so
        // a replayed message collapses onto the existing row on this side too.
        await db.execute(
          'CREATE INDEX messages_chat_seq ON messages (chat_id, seq)',
        );
        await db.execute(
          'CREATE INDEX messages_outbox ON messages (state, created_at)',
        );
      },
    );
    return LocalStore._(db);
  }

  Future<void> upsertChats(List<ChatSummary> chats) async {
    final batch = _db.batch();
    for (final chat in chats) {
      batch.insert('chats', chat.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      final last = chat.lastMessage;
      if (last != null) {
        batch.insert('messages', last.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatSummary>> loadChats() async {
    final rows = await _db.query('chats');
    final chats = <ChatSummary>[];
    for (final row in rows) {
      final id = row['id'] as String;
      chats.add(ChatSummary.fromRow(row, lastMessage: await _lastMessage(id)));
    }
    chats.sort((a, b) {
      final at = a.lastMessage?.createdAt.millisecondsSinceEpoch ?? 0;
      final bt = b.lastMessage?.createdAt.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return chats;
  }

  Future<Message?> _lastMessage(String chatId) async {
    final rows = await _db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'COALESCE(seq, 9223372036854775807) DESC, created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Message.fromRow(rows.first);
  }

  /// Unsent messages sort last: they were composed after everything the server
  /// has acked, and they slot into place once their seq arrives.
  Future<List<Message>> loadMessages(String chatId, {int limit = 100}) async {
    final rows = await _db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'COALESCE(seq, 9223372036854775807) ASC, created_at ASC',
      limit: limit,
    );
    return rows.map(Message.fromRow).toList();
  }

  Future<void> putMessage(Message message) async {
    await _db.insert(
      'messages',
      message.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putMessages(List<Message> messages) async {
    final batch = _db.batch();
    for (final m in messages) {
      batch.insert('messages', m.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// The outbox: everything composed but not yet acked. Drained on every
  /// reconnect, which is what makes "send while offline" work.
  Future<List<Message>> pendingMessages() async {
    final rows = await _db.query(
      'messages',
      where: 'state IN (?, ?)',
      whereArgs: [MessageState.pending.name, MessageState.failed.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(Message.fromRow).toList();
  }

  Future<void> markSent(String clientId, {required String id, required int seq}) async {
    await _db.update(
      'messages',
      {'id': id, 'seq': seq, 'state': MessageState.sent.name},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> markFailed(String clientId) async {
    await _db.update(
      'messages',
      {'state': MessageState.failed.name},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// The sync cursor per chat: the highest seq this device already holds.
  Future<Map<String, int>> syncCursors() async {
    final rows = await _db.rawQuery(
      'SELECT chat_id, COALESCE(MAX(seq), 0) AS last_seq FROM messages GROUP BY chat_id',
    );
    return {
      for (final row in rows) row['chat_id'] as String: (row['last_seq'] as int?) ?? 0,
    };
  }

  Future<void> setReadCursor(String chatId, int upToSeq) async {
    await _db.rawUpdate(
      'UPDATE chats SET read_up_to_seq = MAX(read_up_to_seq, ?) WHERE id = ?',
      [upToSeq, chatId],
    );
  }

  Future<void> clear() async {
    await _db.delete('messages');
    await _db.delete('chats');
  }
}
