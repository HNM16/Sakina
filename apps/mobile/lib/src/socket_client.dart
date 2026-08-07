import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

enum SocketStatus { disconnected, connecting, connected }

/// The single persistent socket.
///
/// Written around the assumption that the connection drops constantly — which
/// on Tajik mobile data outside Dushanbe it does. Reconnect is automatic with
/// exponential backoff and jitter (jitter matters: without it, every client in
/// a cell that just came back reconnects in the same instant and knocks the
/// gateway over again).
class SocketClient {
  SocketClient({required this.wsUrl});

  final String wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  String? _token;
  String? _deviceId;
  int _attempt = 0;
  bool _closedByUser = false;

  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  final _state = StreamController<SocketStatus>.broadcast();

  /// Frames composed while offline. Small on purpose — durable queuing is the
  /// local database's job, not this class's.
  final List<Map<String, dynamic>> _pending = [];

  Stream<Map<String, dynamic>> get frames => _frames.stream;
  Stream<SocketStatus> get connectionState => _state.stream;

  SocketStatus _current = SocketStatus.disconnected;
  SocketStatus get current => _current;

  void _setState(SocketStatus state) {
    _current = state;
    if (!_state.isClosed) _state.add(state);
  }

  Future<void> connect({required String token, required String deviceId}) async {
    _token = token;
    _deviceId = deviceId;
    _closedByUser = false;
    await _open();
  }

  Future<void> _open() async {
    if (_token == null || _deviceId == null) return;

    _setState(SocketStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await channel.ready;
      _channel = channel;

      _subscription = channel.stream.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (Object _) => _onDisconnected(),
        cancelOnError: true,
      );

      // The socket is not usable until `ready` comes back; `hello` must be first.
      _rawSend({
        't': 'hello',
        'd': {'v': 1, 'token': _token, 'device_id': _deviceId},
      });
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onData(dynamic raw) {
    final frame = jsonDecode(raw as String) as Map<String, dynamic>;

    if (frame['t'] == 'ready') {
      _attempt = 0;
      _setState(SocketStatus.connected);
      _startPing();
      for (final queued in _pending) {
        _rawSend(queued);
      }
      _pending.clear();
    }

    if (!_frames.isClosed) _frames.add(frame);
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _setState(SocketStatus.disconnected);
    if (!_closedByUser) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // 1s, 2s, 4s … capped at 30s, each with up to 30% jitter so a cell tower
    // coming back does not produce a synchronised reconnect stampede.
    final base = min(30000, 1000 * pow(2, _attempt).toInt());
    final jitter = Random().nextInt((base * 0.3).round() + 1);
    _attempt = min(_attempt + 1, 5);

    _reconnectTimer = Timer(Duration(milliseconds: base + jitter), _open);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _rawSend({'t': 'ping', 'd': {}});
    });
  }

  void send(Map<String, dynamic> frame) {
    if (_current == SocketStatus.connected) {
      _rawSend(frame);
    } else {
      _pending.add(frame);
    }
  }

  void _rawSend(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (_) {
      _pending.add(frame);
    }
  }

  Future<void> dispose() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _frames.close();
    await _state.close();
  }
}
