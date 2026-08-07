import 'dart:convert';

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
    final response = await http.Response.fromStream(streamed);

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

  /// Returns the dev code when the API runs a stub provider, so the app is
  /// usable end to end before any email or SMS vendor is wired up.
  ///
  /// Email is the identity that works today; the server also accepts
  /// `kind: 'phone'`, which is what launch in Tajikistan will use.
  Future<String?> requestOtp(String email, {String locale = 'tg'}) async {
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
