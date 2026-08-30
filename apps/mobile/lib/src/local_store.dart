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
      version: 2,
      // v1 -> v2 adds the group and channel columns. An upgrade rather than a
      // wipe: the local database IS the UI's source of truth (see the rule at
      // the end of docs/UX.md), so dropping it on an app update would empty
      // every conversation until the first successful sync — on a bad
      // connection, that is a user staring at nothing.
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          for (final column in const [
            'member_count INTEGER NOT NULL DEFAULT 0',
            "role TEXT NOT NULL DEFAULT 'member'",
            'can_post INTEGER NOT NULL DEFAULT 1',
            'username TEXT',
            'description TEXT',
          ]) {
            await db.execute('ALTER TABLE chats ADD COLUMN $column');
          }
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            title TEXT,
            last_seq INTEGER NOT NULL DEFAULT 0,
            read_up_to_seq INTEGER NOT NULL DEFAULT 0,
            members_json TEXT NOT NULL,
            member_count INTEGER NOT NULL DEFAULT 0,
            role TEXT NOT NULL DEFAULT 'member',
            can_post INTEGER NOT NULL DEFAULT 1,
            username TEXT,
            description TEXT
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
        // Serves the per-chat "newest message" lookup in loadChats() and the
        // ordering in loadMessages(). Without it both degrade to a scan once a
        // chat has real history behind it.
        await db.execute(
          'CREATE INDEX messages_chat_recent ON messages (chat_id, seq DESC, created_at DESC)',
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

  /// Leaving, or being removed.
  ///
  /// The messages go with the chat. Keeping them would mean a "deleted" chat's
  /// history quietly occupying the phone forever, and being re-added would
  /// resurrect it from a cache rather than from the server — which is where the
  /// history the user is actually entitled to now lives.
  Future<void> removeChat(String chatId) async {
    final batch = _db.batch();
    batch.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
    batch.delete('chats', where: 'id = ?', whereArgs: [chatId]);
    await batch.commit(noResult: true);
  }

  /// One query, not one per chat.
  ///
  /// This used to select the chats and then run a separate "last message" query
  /// for each of them, plus a sort in Dart — so a user with thirty chats paid
  /// thirty-one queries every time it ran, on the UI isolate. Because the chat
  /// list was reloaded whenever anything changed, that was the most expensive
  /// thing the app did and it ran on every incoming message.
  ///
  /// The correlated subquery picks each chat's newest message, and ordering
  /// happens inside SQLite where it is free.
  Future<List<ChatSummary>> loadChats() async {
    final rows = await _db.rawQuery(
      'SELECT c.id, c.kind, c.title, c.last_seq, c.read_up_to_seq, c.members_json,'
      '       c.member_count, c.role, c.can_post, c.username, c.description,'
      '       m.client_id AS m_client_id, m.chat_id AS m_chat_id,'
      '       m.sender_id AS m_sender_id, m.payload_json AS m_payload_json,'
      '       m.created_at AS m_created_at, m.id AS m_id, m.seq AS m_seq,'
      '       m.state AS m_state '
      'FROM chats c '
      'LEFT JOIN messages m ON m.client_id = ('
      '  SELECT client_id FROM messages WHERE chat_id = c.id'
      '  ORDER BY COALESCE(seq, 9223372036854775807) DESC, created_at DESC LIMIT 1'
      ') '
      'ORDER BY COALESCE(m.created_at, 0) DESC',
    );

    return rows.map((row) {
      final last = row['m_client_id'] == null
          ? null
          : Message.fromRow(<String, dynamic>{
              'client_id': row['m_client_id'],
              'chat_id': row['m_chat_id'],
              'sender_id': row['m_sender_id'],
              'payload_json': row['m_payload_json'],
              'created_at': row['m_created_at'],
              'id': row['m_id'],
              'seq': row['m_seq'],
              'state': row['m_state'],
            });
      return ChatSummary.fromRow(row, lastMessage: last);
    }).toList();
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
