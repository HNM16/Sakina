import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'ApiException($code): $message';
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken, required this.expiresIn});

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int,
      );
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String? _accessToken;

  set accessToken(String? token) => _accessToken = token;

  /// The long-lived half of the pair. Needed here rather than only in
  /// [Session] because rotating is this client's job — every call site would
  /// otherwise have to know how to recover from a 401, and they would each get
  /// it slightly wrong.
  String? refreshToken;

  /// Called with the rotated pair so it can be written to disk.
  ///
  /// Not optional in practice: the server **rotates** the refresh token on
  /// every use, so a pair that is not persisted works exactly once and then
  /// locks the account out until the next sign-in.
  Future<void> Function(AuthTokens tokens)? onTokensRotated;

  /// Called when the refresh token itself is refused. That is a real end of
  /// session — the only honest response is to sign out.
  Future<void> Function()? onSessionExpired;

  /// The rotation in flight, if any.
  ///
  /// Single-flight on purpose. Opening the app fires several authenticated
  /// requests at once; without this each 401 would start its own refresh, and
  /// because the server rotates on every use, the second one would invalidate
  /// the token the first had just been granted. The bug that produces — signed
  /// out at random, only when the network is busy — is close to unfindable.
  Future<bool>? _rotating;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    bool authenticated = false,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['content-type'] = 'application/json';

    if (authenticated && _accessToken != null) {
      request.headers['authorization'] = 'Bearer $_accessToken';
    }
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _client.send(request);
    var response = await http.Response.fromStream(streamed);

    // A 401 on an authenticated call means the access token aged out — they
    // last fifteen minutes — not that the user is signed out. Rotate and try
    // the request once more. Unauthenticated calls, refresh included, fall
    // straight through, which is what keeps this from recursing.
    if (response.statusCode == 401 && authenticated && await _rotateTokens()) {
      final retry = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers['content-type'] = 'application/json'
        ..headers['authorization'] = 'Bearer $_accessToken';
      if (body != null) retry.body = jsonEncode(body);
      response = await http.Response.fromStream(await _client.send(retry));
    }

    if (response.statusCode == 204) return const {};

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        error?['code'] as String? ?? 'unknown',
        error?['message'] as String? ?? 'request failed (${response.statusCode})',
      );
    }

    return decoded;
  }

  /// Rotates on demand, for a caller that saw the rejection somewhere this
  /// client cannot — the websocket gateway refuses a stale token with an error
  /// frame, not an HTTP status.
  Future<bool> rotateTokensNow() => _rotateTokens();

  /// Rotates the token pair, at most one rotation at a time.
  ///
  /// Returns whether the caller now holds a usable access token.
  Future<bool> _rotateTokens() {
    final existing = _rotating;
    if (existing != null) return existing;

    final started = _performRotation();
    _rotating = started;
    unawaited(started.whenComplete(() => _rotating = null));
    return started;
  }

  Future<bool> _performRotation() async {
    final token = refreshToken;
    if (token == null) {
      await onSessionExpired?.call();
      return false;
    }
    try {
      final rotated = await refresh(token);
      _accessToken = rotated.accessToken;
      refreshToken = rotated.refreshToken;
      await onTokensRotated?.call(rotated);
      return true;
    } catch (err) {
      // The refresh token is dead, revoked or already spent. Nothing left to
      // try, and retrying is how a broken session becomes a request loop.
      debugPrint('token refresh failed, ending session: $err');
      await onSessionExpired?.call();
      return false;
    }
  }

  /// Returns the dev code when the API runs a stub provider, so the app is
  /// usable end to end before any email or SMS vendor is wired up.
  ///
  /// Email is the identity that works today; the server also accepts
  /// `kind: 'phone'`, which is what launch in Tajikistan will use.
  Future<String?> requestOtp(String email, {String locale = 'ru'}) async {
    final res = await _send('POST', '/v1/auth/otp/request', body: {
      'identity': {'kind': 'email', 'value': email},
      'locale': locale,
    });
    return res['dev_code'] as String?;
  }

  Future<({PublicUser user, AuthTokens tokens, bool isNewUser})> verifyOtp({
    required String email,
    required String code,
    required String deviceId,
    required String deviceName,
    String? inviteCode,
  }) async {
    final res = await _send('POST', '/v1/auth/otp/verify', body: {
      'identity': {'kind': 'email', 'value': email},
      'code': code,
      'device': {
        'device_id': deviceId,
        'platform': 'android',
        'name': deviceName,
      },
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
    });

    return (
      user: PublicUser.fromJson(Map<String, dynamic>.from(res['user'] as Map)),
      tokens: AuthTokens.fromJson(Map<String, dynamic>.from(res['tokens'] as Map)),
      isNewUser: res['is_new_user'] as bool? ?? false,
    );
  }

  /// Hands the OS-issued push token to the server. Called after the user grants
  /// notification permission, and again whenever the platform rotates it.
  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    required String provider,
  }) async {
    await _send(
      'POST',
      '/v1/devices/push-token',
      body: {'device_id': deviceId, 'token': token, 'provider': provider},
      authenticated: true,
    );
  }

  /// Turning notifications off, and what sign-out calls.
  Future<void> clearPushToken() async {
    await _send('DELETE', '/v1/devices/push-token', authenticated: true);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final res = await _send('POST', '/v1/auth/refresh', body: {'refresh_token': refreshToken});
    return AuthTokens.fromJson(res);
  }

  Future<List<ChatSummary>> listChats() async {
    final res = await _send('GET', '/v1/chats', authenticated: true);
    return (res['chats'] as List<dynamic>)
        .map((c) => ChatSummary.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  Future<ChatSummary> createDirectChat(String peerId) async {
    final res = await _send(
      'POST',
      '/v1/chats',
      body: {'kind': 'direct', 'peer_id': peerId},
      authenticated: true,
    );
    return ChatSummary.fromJson(res);
  }

  Future<ChatSummary> createGroup({
    required String title,
    required List<String> memberIds,
    String? description,
  }) async {
    final res = await _send(
      'POST',
      '/v1/chats',
      body: {
        'kind': 'group',
        'title': title,
        'member_ids': memberIds,
        if (description != null && description.isNotEmpty) 'description': description,
      },
      authenticated: true,
    );
    return ChatSummary.fromJson(res);
  }

  /// A channel with no [username] stays private: subscribers are added, not
  /// found. With one, anybody who has the handle can join.
  Future<ChatSummary> createChannel({
    required String title,
    String? username,
    String? description,
    List<String> memberIds = const [],
  }) async {
    final res = await _send(
      'POST',
      '/v1/chats',
      body: {
        'kind': 'channel',
        'title': title,
        'member_ids': memberIds,
        if (username != null && username.isNotEmpty) 'username': username.toLowerCase(),
        if (description != null && description.isNotEmpty) 'description': description,
      },
      authenticated: true,
    );
    return ChatSummary.fromJson(res);
  }

  Future<ChatSummary> joinChannel(String username) async {
    final res = await _send(
      'POST',
      '/v1/chats/join',
      body: {'username': username.toLowerCase().replaceFirst('@', '')},
      authenticated: true,
    );
    return ChatSummary.fromJson(res);
  }

  Future<void> addMembers(String chatId, List<String> userIds) async {
    await _send(
      'POST',
      '/v1/chats/$chatId/members',
      body: {'user_ids': userIds},
      authenticated: true,
    );
  }

  /// Removing someone, or — when [userId] is your own — leaving.
  Future<void> removeMember(String chatId, String userId) async {
    await _send('DELETE', '/v1/chats/$chatId/members/$userId', authenticated: true);
  }

  Future<void> setRole(String chatId, String userId, String role) async {
    await _send(
      'POST',
      '/v1/chats/$chatId/role',
      body: {'user_id': userId, 'role': role},
      authenticated: true,
    );
  }

  Future<ChatSummary> updateChat(
    String chatId, {
    String? title,
    String? description,
  }) async {
    final res = await _send(
      'PATCH',
      '/v1/chats/$chatId',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      },
      authenticated: true,
    );
    return ChatSummary.fromJson(res);
  }

  Future<({List<ChatMember> members, int total})> listMembers(
    String chatId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _send(
      'GET',
      '/v1/chats/$chatId/members?limit=$limit&offset=$offset',
      authenticated: true,
    );
    return (
      members: (res['members'] as List<dynamic>)
          .map((m) => ChatMember.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      total: (res['total'] as num).toInt(),
    );
  }

  /// Step one of sending an attachment: ask where to put the bytes.
  ///
  /// Authorisation happens here, before anything is uploaded — which is also
  /// why a channel subscriber gets refused at this point rather than after
  /// spending their data allowance on a video nobody will see.
  Future<UploadTicket> requestUpload({
    required String chatId,
    required String name,
    required String mime,
    required int size,
    bool thumbnail = false,
  }) async {
    final res = await _send(
      'POST',
      '/v1/media/upload',
      body: {
        'chat_id': chatId,
        'name': name,
        'mime': mime,
        'size': size,
        'thumbnail': thumbnail,
      },
      authenticated: true,
    );
    return UploadTicket.fromJson(res);
  }

  /// A short-lived URL for reading an attachment back. Re-authorised every
  /// time, so leaving a group stops working immediately.
  Future<String> mediaUrl({required String chatId, required String key}) async {
    final res = await _send(
      'GET',
      '/v1/media/url?chat_id=$chatId&key=${Uri.encodeQueryComponent(key)}',
      authenticated: true,
    );
    return res['url'] as String;
  }

  /// Deep backfill for scroll-back, and for clients too far behind to catch up
  /// on the socket.
  Future<({List<Message> messages, bool hasMore})> history(
    String chatId, {
    int? beforeSeq,
    int limit = 50,
  }) async {
    final query = StringBuffer('?limit=$limit');
    if (beforeSeq != null) query.write('&before_seq=$beforeSeq');

    final res = await _send('GET', '/v1/chats/$chatId/messages$query', authenticated: true);
    return (
      messages: (res['messages'] as List<dynamic>)
          .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      hasMore: res['has_more'] as bool,
    );
  }
}

/// A ticket to upload one file, plus what the server decided about it.
///
/// `kind` comes back from the server rather than being guessed here: the server
/// classifies by mime type and refuses some outright, and a client that decided
/// for itself could label an executable as a photo.
class UploadTicket {
  const UploadTicket({
    required this.key,
    required this.url,
    required this.method,
    required this.headers,
    required this.kind,
    required this.maxSize,
  });

  final String key;
  final String url;
  final String method;
  final Map<String, String> headers;
  final String kind;
  final int maxSize;

  factory UploadTicket.fromJson(Map<String, dynamic> json) => UploadTicket(
        key: json['key'] as String,
        url: json['url'] as String,
        method: json['method'] as String? ?? 'PUT',
        headers: Map<String, String>.from(
          (json['headers'] as Map?) ?? const <String, String>{},
        ),
        kind: json['kind'] as String? ?? 'file',
        maxSize: (json['max_size'] as num?)?.toInt() ?? 0,
      );
}

class ChatMember {
  const ChatMember({required this.user, required this.role});
  final PublicUser user;
  final String role;

  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
        user: PublicUser.fromJson(json),
        role: json['role'] as String? ?? 'member',
      );
}
