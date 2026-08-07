import 'package:flutter/material.dart';

import 'src/api_client.dart';
import 'src/chat_repository.dart';
import 'src/l10n.dart';
import 'src/local_store.dart';
import 'src/session.dart';
import 'src/socket_client.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _signOut() async {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seed: const Color(0xFF1B7F5F)),
        useMaterial3: true,
      ),
      // Includes the Tajik fallback delegates — Flutter has no `tg` locale of
      // its own. See lib/src/l10n.dart.
      localizationsDelegates: localizationDelegates,
      supportedLocales: L10n.supportedLocales,
      home: repository == null
          ? AuthScreen(
              api: _api,
              session: widget.session,
              onSignedIn: _startSession,
            )
          : ChatListScreen(repository: repository, onSignOut: _signOut),
    );
  }
}
