import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Persisted credentials and device identity.
///
/// `deviceId` is generated once per install and never changes. It is what makes
/// this install addressable on its own: sessions, push tokens and per-device
/// revocation all hang off it.
class Session {
  Session._(this._prefs);

  final SharedPreferences _prefs;

  static const _kDeviceId = 'device_id';
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kDisplayName = 'display_name';

  static Future<Session> load() async {
    final prefs = await SharedPreferences.getInstance();
    final session = Session._(prefs);
    if (session._prefs.getString(_kDeviceId) == null) {
      await session._prefs.setString(_kDeviceId, const Uuid().v4());
    }
    return session;
  }

  String get deviceId => _prefs.getString(_kDeviceId)!;
  String? get accessToken => _prefs.getString(_kAccessToken);
  String? get refreshToken => _prefs.getString(_kRefreshToken);
  String? get userId => _prefs.getString(_kUserId);
  String? get displayName => _prefs.getString(_kDisplayName);

  bool get isAuthenticated => accessToken != null && userId != null;

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required PublicUser user,
  }) async {
    await _prefs.setString(_kAccessToken, accessToken);
    await _prefs.setString(_kRefreshToken, refreshToken);
    await _prefs.setString(_kUserId, user.id);
    await _prefs.setString(_kDisplayName, user.displayName);
  }

  Future<void> updateTokens({required String accessToken, required String refreshToken}) async {
    await _prefs.setString(_kAccessToken, accessToken);
    await _prefs.setString(_kRefreshToken, refreshToken);
  }

  Future<void> clear() async {
    // The device id survives sign-out: it identifies the install, not the account.
    for (final key in [_kAccessToken, _kRefreshToken, _kUserId, _kDisplayName]) {
      await _prefs.remove(key);
    }
  }
}
