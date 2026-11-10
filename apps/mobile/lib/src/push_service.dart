import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'l10n.dart';

/// Notifications for when the app is closed.
///
/// The socket only exists while the app is alive. Once Android or iOS suspends
/// it, the connection is gone and nothing Sakina does can keep it — so delivery
/// to a closed app has to go through FCM and APNs. There is no alternative.
///
/// Two things about how this is wired, both deliberate:
///
/// **The payload carries no message text.** It carries a chat id and a seq. The
/// app wakes, opens its socket, syncs, and reads the real text out of its own
/// SQLite. Putting content in the payload would mean handing message text to
/// Google and Apple, and it would have to be undone the moment end-to-end
/// encryption arrives.
///
/// **The notification shown on the lock screen is composed locally**, from data
/// the device already has. That is what makes "Салом, чӣ хел?" appear on the
/// lock screen without it ever having travelled through a push service.
///
/// FCM is used for both platforms — on iOS it forwards to APNs — because one
/// integration is less to keep working than two.
class PushService {
  PushService({required this.api, required this.onMessageForChat});

  final ApiClient api;

  /// Called when a push arrives for a chat, so the repository can sync it.
  final void Function(String chatId) onMessageForChat;

  static const _androidChannel = AndroidNotificationChannel(
    'sakina_messages',
    'Паёмҳо',
    description: 'Огоҳиномаҳо дар бораи паёмҳои нав',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;

  /// Returns false when the user declined notifications — not an error, just a
  /// choice. Everything else keeps working; they simply see messages when they
  /// open the app.
  Future<bool> start(String deviceId) async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted) {
      debugPrint('push: permission not granted');
      return false;
    }

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // The system alert is suppressed in the foreground so the app can
          // decide: if the chat is already open, a banner is noise.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    await _registerToken(messaging, deviceId);

    // Tokens rotate more often than people expect — reinstalls, restores from
    // backup, some OS updates. A stale token is a silently undelivered message.
    _tokenSub = messaging.onTokenRefresh.listen((token) {
      unawaited(_sendToken(token, deviceId));
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromNotification);

    return true;
  }

  Future<void> _registerToken(FirebaseMessaging messaging, String deviceId) async {
    // On iOS the APNs token can lag behind the FCM one just after launch;
    // asking for it first avoids registering a token that cannot yet deliver.
    if (Platform.isIOS) {
      final apns = await messaging.getAPNSToken();
      if (apns == null) {
        debugPrint('push: APNs token not ready yet');
      }
    }

    final token = await messaging.getToken();
    if (token != null) await _sendToken(token, deviceId);
  }

  Future<void> _sendToken(String token, String deviceId) async {
    try {
      // `fcm` for both platforms: on iOS, FCM forwards to APNs, so the server
      // only ever talks to one provider.
      await api.registerPushToken(deviceId: deviceId, token: token, provider: 'fcm');
    } catch (err) {
      debugPrint('push: could not register token: $err');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final chatId = message.data['chat_id'];
    if (chatId is! String) return;

    // The app is open, so the socket will deliver it. Just nudge the sync and
    // show nothing — a banner for a message already on screen is why people
    // mute apps.
    onMessageForChat(chatId);
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    final chatId = message.data['chat_id'];
    if (chatId is String) onMessageForChat(chatId);
  }

  /// Composes the lock-screen notification from local data, after the payload
  /// has told us *which* chat changed. Called from the background handler.
  static Future<void> showLocal({
    required String chatId,
    required String title,
    required String body,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.show(
      chatId.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          // One notification per chat, replaced rather than stacked — ten
          // unread messages should not be ten rows in the shade.
          tag: chatId,
        ),
        iOS: const DarwinNotificationDetails(threadIdentifier: 'sakina'),
      ),
      payload: chatId,
    );
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
  }
}

/// Runs in a separate isolate when a push arrives with the app terminated.
///
/// Must be a top-level function — Flutter looks it up by name across the
/// isolate boundary, so it cannot be a method or a closure.
///
/// Deliberately minimal: no database, no socket. Just the generic notification
/// the payload already carries. Enriching it with the real message text needs
/// the local database, which belongs in an iOS Notification Service Extension
/// and an Android enrichment step — worth doing, and not before the basic path
/// is proven on real hardware.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final chatId = message.data['chat_id'];
  if (chatId is! String) return;

  final copy = const L10n(Locale('tg'));
  await PushService.showLocal(
    chatId: chatId,
    title: copy.t('app_name'),
    body: copy.t('push_new_message'),
  );
}
