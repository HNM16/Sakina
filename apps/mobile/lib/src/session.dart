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
  static const _kLanguage = 'language';
  static const _kTheme = 'theme';

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

  /// The language the user picked, or null to follow the phone.
  ///
  /// Survives sign-out along with the device id: someone who chose Tajik on a
  /// Russian-locale handset should not have to choose it again after signing
  /// back in.
  String? get language => _prefs.getString(_kLanguage);

  /// The theme the user picked, or null to follow the phone.
  ///
  /// Stored as the theme's id rather than its index: a list position changes
  /// the moment a theme is inserted above it, and the setting would silently
  /// become a different theme on update.
  String? get theme => _prefs.getString(_kTheme);

  Future<void> setTheme(String? id) async {
    if (id == null) {
      await _prefs.remove(_kTheme);
    } else {
      await _prefs.setString(_kTheme, id);
    }
  }

  Future<void> setLanguage(String? code) async {
    if (code == null) {
      await _prefs.remove(_kLanguage);
    } else {
      await _prefs.setString(_kLanguage, code);
    }
  }

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
    // The device id, the language and the theme survive sign-out: one
    // identifies the install, the others are preferences of the person
    // install, the other is a preference of the person holding it.
    for (final key in [_kAccessToken, _kRefreshToken, _kUserId, _kDisplayName]) {
      await _prefs.remove(key);
    }
  }
}
