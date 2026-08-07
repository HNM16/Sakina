import 'dart:convert';

/// Dart mirror of `packages/protocol`.
///
/// Hand-written because Flutter cannot import the TypeScript schemas. That
/// makes `docs/PROTOCOL.md` the single source of truth and these classes a copy
/// that has to be kept honest — the reason the plan swaps JSON for protobuf
/// around M2, once the frame set stops changing.

enum MessageState { pending, sent, failed }

class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    this.username,
    this.avatarKey,
    this.kind = 'human',
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarKey;
  final String kind;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        username: json['username'] as String?,
        avatarKey: json['avatar_key'] as String?,
        kind: json['kind'] as String? ?? 'human',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'username': username,
        'avatar_key': avatarKey,
        'kind': kind,
      };
}

class Message {
  const Message({
    required this.clientId,
    required this.chatId,
    required this.senderId,
    required this.payload,
    required this.createdAt,
    this.id,
    this.seq,
    this.state = MessageState.sent,
  });

  /// Generated on this device before the message is sent. Survives retries
  /// unchanged — it is what stops a resend from becoming a duplicate.
  final String clientId;
  final String chatId;
  final String senderId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Null until the server acks. Both are assigned server-side.
  final String? id;
  final int? seq;

  final MessageState state;

  String get type => payload['type'] as String? ?? 'text';
  String get text => payload['text'] as String? ?? '';

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        clientId: json['client_id'] as String,
        chatId: json['chat_id'] as String,
        senderId: json['sender_id'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
        id: json['id'] as String?,
        seq: json['seq'] as int?,
      );

  Map<String, dynamic> toRow() => {
        'client_id': clientId,
        'chat_id': chatId,
        'sender_id': senderId,
        'payload_json': jsonEncode(payload),
        'created_at': createdAt.millisecondsSinceEpoch,
        'id': id,
        'seq': seq,
        'state': state.name,
      };

  factory Message.fromRow(Map<String, dynamic> row) => Message(
        clientId: row['client_id'] as String,
        chatId: row['chat_id'] as String,
        senderId: row['sender_id'] as String,
        payload: Map<String, dynamic>.from(
          jsonDecode(row['payload_json'] as String) as Map,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        id: row['id'] as String?,
        seq: row['seq'] as int?,
        state: MessageState.values.firstWhere(
          (s) => s.name == row['state'],
          orElse: () => MessageState.sent,
        ),
      );

  Message copyWith({String? id, int? seq, MessageState? state}) => Message(
        clientId: clientId,
        chatId: chatId,
        senderId: senderId,
        payload: payload,
        createdAt: createdAt,
        id: id ?? this.id,
        seq: seq ?? this.seq,
        state: state ?? this.state,
      );
}

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.kind,
    required this.lastSeq,
    required this.readUpToSeq,
    required this.members,
    this.title,
    this.lastMessage,
  });

  final String id;
  final String kind;
  final int lastSeq;
  final int readUpToSeq;
  final List<PublicUser> members;
  final String? title;
  final Message? lastMessage;

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        kind: json['kind'] as String,
        lastSeq: json['last_seq'] as int,
        readUpToSeq: json['read_up_to_seq'] as int,
        members: (json['members'] as List<dynamic>)
            .map((m) => PublicUser.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        title: json['title'] as String?,
        lastMessage: json['last_message'] == null
            ? null
            : Message.fromJson(Map<String, dynamic>.from(json['last_message'] as Map)),
      );

  /// Direct chats have no stored title — they are named after the other person.
  String displayTitle(String selfId) {
    if (title != null && title!.isNotEmpty) return title!;
    final others = members.where((m) => m.id != selfId).toList();
    if (others.isEmpty) return 'Saved messages';
    return others.map((m) => m.displayName).join(', ');
  }

  int get unreadCount => lastSeq > readUpToSeq ? lastSeq - readUpToSeq : 0;

  Map<String, dynamic> toRow() => {
        'id': id,
        'kind': kind,
        'title': title,
        'last_seq': lastSeq,
        'read_up_to_seq': readUpToSeq,
        'members_json': jsonEncode(members.map((m) => m.toJson()).toList()),
      };

  factory ChatSummary.fromRow(Map<String, dynamic> row, {Message? lastMessage}) => ChatSummary(
        id: row['id'] as String,
        kind: row['kind'] as String,
        lastSeq: row['last_seq'] as int,
        readUpToSeq: row['read_up_to_seq'] as int,
        members: (jsonDecode(row['members_json'] as String) as List<dynamic>)
            .map((m) => PublicUser.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        title: row['title'] as String?,
        lastMessage: lastMessage,
      );
}
