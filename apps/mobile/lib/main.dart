import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'src/api_client.dart';
import 'src/chat_repository.dart';
import 'src/l10n.dart';
import 'src/local_store.dart';
import 'src/push_service.dart';
import 'src/session.dart';
import 'src/socket_client.dart';
import 'src/theme.dart';
import 'src/ui/auth_screen.dart';
import 'src/ui/chat_list_screen.dart';

/// Endpoints are compile-time so a release build cannot be pointed at a dev
/// server by accident:
///   flutter run --dart-define=API_URL=http://10.0.2.2:4000 \
///               --dart-define=WS_URL=ws://10.0.2.2:4001/ws
///
/// 10.0.2.2 is how the Android emulator reaches the host machine.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:4000');
const wsUrl = String.fromEnvironment('WS_URL', defaultValue: 'ws://10.0.2.2:4001/ws');

/// Push is optional at build time: without a Firebase config the app still
/// runs, it just never notifies. That keeps the project buildable before anyone
/// has set up a Firebase account.
bool pushAvailable = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    // Registered before runApp so a push arriving with the app terminated can
    // still be handled — Flutter looks this up by name in a fresh isolate.
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    pushAvailable = true;
  } catch (err) {
    debugPrint('push unavailable (no Firebase config?): $err');
  }

  final session = await Session.load();
  final store = await LocalStore.open();

  runApp(SakinaApp(session: session, store: store));
}

class SakinaApp extends StatefulWidget {
  const SakinaApp({super.key, required this.session, required this.store});

  final Session session;
  final LocalStore store;

  @override
  State<SakinaApp> createState() => _SakinaAppState();
}

class _SakinaAppState extends State<SakinaApp> {
  late final ApiClient _api = ApiClient(baseUrl: apiUrl);
  SocketClient? _socket;
  ChatRepository? _repository;
  PushService? _push;

  /// null means "follow the phone", which resolves to Russian for a phone set
  /// to anything we do not speak. See src/l10n.dart.
  Locale? _locale;

  Future<void> _setLanguage(String? code) async {
    await widget.session.setLanguage(code);
    if (!mounted) return;
    setState(() => _locale = code == null ? null : Locale(code));
  }

  @override
  void initState() {
    super.initState();
    final saved = widget.session.language;
    if (saved != null) _locale = Locale(saved);
    if (widget.session.isAuthenticated) {
      _api.accessToken = widget.session.accessToken;
      _startSession();
    }
  }

  Future<void> _startSession() async {
    final socket = SocketClient(wsUrl: wsUrl);
    final repository = ChatRepository(
      api: _api,
      store: widget.store,
      socket: socket,
      selfId: widget.session.userId!,
    );

    // Local data first, network second: the chat list is on screen before the
    // socket has even opened.
    await repository.bootstrap();

    await socket.connect(
      token: widget.session.accessToken!,
      deviceId: widget.session.deviceId,
    );

    if (!mounted) return;
    setState(() {
      _socket = socket;
      _repository = repository;
    });

    if (pushAvailable) {
      // Asked for after the chat list is on screen, not on the splash. A
      // permission prompt makes far more sense once someone can see what it is
      // they would be notified about.
      final push = PushService(
        api: _api,
        // A push only says which chat changed; the repository does the rest.
        onMessageForChat: (_) => unawaited(repository.resync()),
      );
      await push.start(widget.session.deviceId);
      _push = push;
    }
  }

  Future<void> _signOut() async {
    // Detach the token first: a signed-out device must stop being notified.
    try {
      await _api.clearPushToken();
    } catch (_) {
      // Best effort — never block sign-out on it.
    }
    await _push?.dispose();
    _push = null;
    await _socket?.dispose();
    _repository?.dispose();
    await widget.store.clear();
    await widget.session.clear();

    if (!mounted) return;
    setState(() {
      _socket = null;
      _repository = null;
    });
  }

  @override
  void dispose() {
    _push?.dispose();
    _socket?.dispose();
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;

    return MaterialApp(
      title: 'Sakina',
      debugShowCheckedModeBanner: false,
      // Dark by default: cheaper on battery, readable in mountain sun, and
      // honest to a name that means stillness. See src/theme.dart.
      theme: SakinaTheme.day(),
      darkTheme: SakinaTheme.night(),
      themeMode: ThemeMode.dark,
      // Includes the Tajik fallback delegates — Flutter has no `tg` locale of
      // its own. See lib/src/l10n.dart.
      localizationsDelegates: localizationDelegates,
      supportedLocales: L10n.supportedLocales,
      // null hands resolution back to the phone, which falls through to the
      // first supported locale — Russian.
      locale: _locale,
      home: repository == null
          ? AuthScreen(
              api: _api,
              session: widget.session,
              onSignedIn: _startSession,
            )
          : ChatListScreen(
              repository: repository,
              onSignOut: _signOut,
              language: widget.session.language,
              onLanguageChanged: _setLanguage,
            ),
    );
  }
}
