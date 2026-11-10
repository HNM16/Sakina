// The client keeping itself signed in.
//
// Access tokens last fifteen minutes. Everything here is about what happens at
// minute sixteen, which before this was: every request 401s, the socket
// reconnects forever against a token the gateway has already refused, and the
// only way out is for the user to sign out and back in.
//
// The single-flight test is the one worth keeping. The server *rotates* the
// refresh token on every use, so two concurrent refreshes do not merely waste
// a round trip — the second spends a token the first has already replaced, and
// the account is signed out. It happens only when several requests are in
// flight at once, which is to say only on a slow connection, which is to say
// only for the people this app is for.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sakina/src/api_client.dart';

/// A server that refuses one named access token and accepts any other.
class _FakeServer {
  _FakeServer({required this.staleToken});

  final String staleToken;
  int refreshCalls = 0;
  int chatCalls = 0;
  String issued = 'access-2';

  /// Set to fail the rotation, standing in for a revoked or spent refresh
  /// token — the case where signing out is the only honest answer.
  bool refuseRefresh = false;

  http.Client get client => MockClient((request) async {
        if (request.url.path == '/v1/auth/refresh') {
          refreshCalls += 1;
          if (refuseRefresh) {
            return http.Response(
              jsonEncode({'error': {'code': 'unauthorized', 'message': 'spent'}}),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'access_token': issued,
              'refresh_token': 'refresh-2',
              'expires_in': 900,
            }),
            200,
          );
        }

        chatCalls += 1;
        if (request.headers['authorization'] == 'Bearer $staleToken') {
          return http.Response(
            jsonEncode({'error': {'code': 'unauthorized', 'message': 'expired'}}),
            401,
          );
        }
        return http.Response(jsonEncode({'chats': <dynamic>[]}), 200);
      });
}

void main() {
  test('an expired access token is rotated and the request retried', () async {
    final server = _FakeServer(staleToken: 'access-1');
    final api = ApiClient(baseUrl: 'http://test', client: server.client)
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';

    AuthTokens? rotated;
    api.onTokensRotated = (tokens) async => rotated = tokens;

    // Succeeds, rather than throwing, which is the whole point.
    await api.listChats();

    expect(server.refreshCalls, 1);
    expect(server.chatCalls, 2, reason: 'the original call and one retry');
    expect(rotated?.accessToken, 'access-2',
        reason: 'the rotated pair has to be handed out for persisting — the '
            'server rotates the refresh token, so an unsaved pair works once');
    expect(rotated?.refreshToken, 'refresh-2');
  });

  test('concurrent expiries rotate exactly once', () async {
    final server = _FakeServer(staleToken: 'access-1');
    final api = ApiClient(baseUrl: 'http://test', client: server.client)
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';

    await Future.wait([
      api.listChats(),
      api.listChats(),
      api.listChats(),
      api.listChats(),
    ]);

    expect(server.refreshCalls, 1,
        reason: 'a second rotation would spend the token the first was just '
            'granted, and sign the user out at random');
  });

  test('a refused refresh ends the session rather than looping', () async {
    final server = _FakeServer(staleToken: 'access-1')..refuseRefresh = true;
    final api = ApiClient(baseUrl: 'http://test', client: server.client)
      ..accessToken = 'access-1'
      ..refreshToken = 'dead';

    var expired = 0;
    api.onSessionExpired = () async => expired += 1;

    await expectLater(api.listChats(), throwsA(isA<ApiException>()));
    expect(expired, 1);
    expect(server.refreshCalls, 1, reason: 'tried once, not in a loop');
  });

  test('with no refresh token at all the session ends immediately', () async {
    final server = _FakeServer(staleToken: 'access-1');
    final api = ApiClient(baseUrl: 'http://test', client: server.client)
      ..accessToken = 'access-1';

    var expired = 0;
    api.onSessionExpired = () async => expired += 1;

    await expectLater(api.listChats(), throwsA(isA<ApiException>()));
    expect(expired, 1);
    expect(server.refreshCalls, 0, reason: 'nothing to rotate with');
  });
}
