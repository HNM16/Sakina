// MOTION: SECTION — signing in replaces the whole world, so it fades rather
// than travels. It is not somewhere deeper, and it is not a sibling tab
// either; the fade is what those two have in common.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'src/api_client.dart';
import 'src/chat_repository.dart';
import 'src/l10n.dart';
import 'src/local_store.dart';
import 'src/media_service.dart';
import 'src/push_service.dart';
import 'src/motion.dart';
import 'src/session.dart';
import 'src/socket_client.dart';
import 'src/ui/auth/auth_screen.dart';
import 'src/ui/sections/section.dart';
import 'src/ui/shell.dart';
import 'src/ui/themes/themes.dart';

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
  late final MediaService _media = MediaService(_api);
  SocketClient? _socket;
  ChatRepository? _repository;
  PushService? _push;

  /// null means "follow the phone", which resolves to Russian for a phone set
  /// to anything we do not speak. See src/l10n.dart.
  Locale? _locale;

  /// The chosen theme's id, or null to follow the phone. See src/ui/themes/.
  String? _themeId;

  Future<void> _setTheme(String? id) async {
    await widget.session.setTheme(id);
    if (!mounted) return;
    setState(() => _themeId = id);
  }

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
    _themeId = widget.session.theme;
    if (widget.session.isAuthenticated) {
      _startSession();
    }
  }

  /// Teaches the API client how to keep itself signed in.
  ///
  /// Access tokens last fifteen minutes. Before this existed, minute sixteen
  /// turned every request into a 401 and the socket into a reconnect loop
  /// against a token the gateway had already refused — and the only way out
  /// was for the user to sign out and back in. `ApiClient.refresh` and
  /// `Session.updateTokens` were both already written; nothing called either.
  void _armTokenRotation() {
    _api.accessToken = widget.session.accessToken;
    _api.refreshToken = widget.session.refreshToken;

    // The server rotates the refresh token on every use, so persisting the new
    // pair is not bookkeeping — a pair that is not saved works exactly once.
    _api.onTokensRotated = (tokens) async {
      await widget.session.updateTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      // The socket authenticates once, at hello, so it is holding the old
      // token until it is told otherwise.
      await _socket?.updateToken(tokens.accessToken);
    };

    _api.onSessionExpired = () async {
      if (!mounted) return;
      await _signOut();
    };
  }

  Future<void> _startSession() async {
    // Here rather than in initState, because there are two ways to reach a
    // signed-in app and only one of them goes through initState. Arming this
    // on the resume path alone left every *fresh* sign-in with no refresh
    // token on the client, so the first expiry after signing in threw an
    // unauthorized exception instead of rotating — which is exactly what
    // running it showed.
    _armTokenRotation();

    final socket = SocketClient(wsUrl: wsUrl);

    // When the gateway refuses the token, ask the API client to rotate. A
    // successful rotation calls onTokensRotated above, which hands the socket
    // its new token and reconnects it; a failed one signs out.
    socket.onUnauthorized = () async {
      await _api.rotateTokensNow();
    };
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
    final chosenTheme = SakinaThemes.byId(_themeId);

    return MaterialApp(
      title: 'Sakina',
      debugShowCheckedModeBanner: false,
      // Dark by default: cheaper on battery, readable in mountain sun, and
      // honest to a name that means stillness. See src/theme.dart.
      // A chosen theme is served whatever the phone is set to; no choice hands
      // the decision back to the phone. `themeMode` used to be pinned to dark,
      // which made the light theme unreachable — it was fully written and no
      // user could ever see it.
      theme: (chosenTheme ?? SakinaThemes.systemLight).build(),
      darkTheme: (chosenTheme ?? SakinaThemes.systemDark).build(),
      themeMode: chosenTheme == null
          ? ThemeMode.system
          : (chosenTheme.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light),
      // Includes the Tajik fallback delegates — Flutter has no `tg` locale of
      // its own. See lib/src/l10n.dart.
      localizationsDelegates: localizationDelegates,
      supportedLocales: L10n.supportedLocales,
      // null hands resolution back to the phone, which falls through to the
      // first supported locale — Russian.
      locale: _locale,
      // Signing in is not a push and not a tab change: it replaces the whole
      // world. So it gets its own motion, and the vocabulary already had the
      // right one — see _SignedInTransition.
      home: AnimatedSwitcher(
        duration: SakinaMotion.duration(context, SakinaMotion.long),
        switchInCurve: SakinaMotion.settle,
        switchOutCurve: SakinaMotion.leave,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: repository == null
            ? AuthScreen(
                key: const ValueKey('auth'),
                api: _api,
                session: widget.session,
                onSignedIn: _startSession,
                onLanguageChanged: _setLanguage,
              )
            : SakinaShell(
                key: const ValueKey('shell'),
                scope: SectionScope(
                  repository: repository,
                  media: _media,
                  selfName: widget.session.displayName,
                  language: widget.session.language,
                  onLanguageChanged: _setLanguage,
                  themeId: _themeId,
                  onThemeChanged: _setTheme,
                  onSignOut: _signOut,
                ),
              ),
      ),
    );
  }
}
