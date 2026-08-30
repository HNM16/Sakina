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

  bool get isMedia => type == 'media';

  /// The `seq` of the message this one answers, or null.
  ///
  /// seq rather than id because it is per-chat and gapless, so resolving a
  /// quote is a lookup in the list already in memory. A quote whose target is
  /// not loaded renders as unavailable rather than failing — the reply is still
  /// a real message.
  int? get replyToSeq => (payload['reply_to_seq'] as num?)?.toInt();

  /// image | video | file, decided by the SERVER from the mime type. A client
  /// that trusted its own guess here would render an executable as a photo.
  String get mediaKind => payload['kind'] as String? ?? 'file';
  String? get mediaKey => payload['key'] as String?;
  String? get thumbKey => payload['thumb_key'] as String?;
  String? get mediaName => payload['name'] as String?;
  String? get caption => payload['caption'] as String?;
  int get mediaSize => (payload['size'] as num?)?.toInt() ?? 0;
  int? get durationMs => (payload['duration_ms'] as num?)?.toInt();
  double? get mediaWidth => (payload['width'] as num?)?.toDouble();
  double? get mediaHeight => (payload['height'] as num?)?.toDouble();

  /// What a chat list row shows instead of the message body. A photo has no
  /// text, and "" in the list looks like a bug rather than an attachment.
  String previewText(String Function(String) t) {
    if (type == 'text') return text;
    if (type == 'system') return t('system_event');
    if (!isMedia) return t('attachment');
    final caption = this.caption;
    if (caption != null && caption.isNotEmpty) return caption;
    return switch (mediaKind) {
      'image' => t('a_photo'),
      'video' => t('a_video'),
      _ => mediaName ?? t('a_file'),
    };
  }

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
    this.memberCount = 0,
    this.role = 'member',
    this.canPost = true,
    this.username,
    this.description,
    this.title,
    this.lastMessage,
  });

  final String id;
  final String kind;
  final int lastSeq;
  final int readUpToSeq;

  /// A sample, not the whole list — a channel's subscribers are not shipped in
  /// the chat list. [memberCount] is the real number.
  final List<PublicUser> members;
  final int memberCount;

  /// owner | admin | member, for the signed-in user.
  final String role;

  /// Whether this user may post here. False for a channel subscriber.
  ///
  /// The server sends it so the composer can be hidden rather than shown and
  /// then rejected. It is never the enforcement — the server re-checks on every
  /// send, and this field being wrong costs a confusing error, not a leak.
  final bool canPost;

  final String? username;
  final String? description;
  final String? title;
  final Message? lastMessage;

  bool get isDirect => kind == 'direct';
  bool get isGroup => kind == 'group';
  bool get isChannel => kind == 'channel';
  bool get isAdmin => role == 'owner' || role == 'admin';

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        kind: json['kind'] as String,
        lastSeq: json['last_seq'] as int,
        readUpToSeq: json['read_up_to_seq'] as int,
        members: (json['members'] as List<dynamic>)
            .map((m) => PublicUser.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        role: json['role'] as String? ?? 'member',
        canPost: json['can_post'] as bool? ?? true,
        username: json['username'] as String?,
        description: json['description'] as String?,
        title: json['title'] as String?,
        lastMessage: json['last_message'] == null
            ? null
            : Message.fromJson(Map<String, dynamic>.from(json['last_message'] as Map)),
      );

  /// Direct chats have no stored title — they are named after the other person.
  ///
  /// [savedLabel] is passed in rather than hardcoded because this is
  /// user-visible text and every string in this app comes from L10n.
  String displayTitle(String selfId, {String savedLabel = ''}) {
    if (title != null && title!.isNotEmpty) return title!;
    final others = members.where((m) => m.id != selfId).toList();
    if (others.isEmpty) return savedLabel;
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
        'member_count': memberCount,
        'role': role,
        // SQLite has no boolean; 1/0 and back.
        'can_post': canPost ? 1 : 0,
        'username': username,
        'description': description,
      };

  factory ChatSummary.fromRow(Map<String, dynamic> row, {Message? lastMessage}) => ChatSummary(
        id: row['id'] as String,
        kind: row['kind'] as String,
        lastSeq: row['last_seq'] as int,
        readUpToSeq: row['read_up_to_seq'] as int,
        members: (jsonDecode(row['members_json'] as String) as List<dynamic>)
            .map((m) => PublicUser.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        memberCount: (row['member_count'] as int?) ?? 0,
        role: row['role'] as String? ?? 'member',
        canPost: (row['can_post'] as int?) != 0,
        username: row['username'] as String?,
        description: row['description'] as String?,
        title: row['title'] as String?,
        lastMessage: lastMessage,
      );
}
