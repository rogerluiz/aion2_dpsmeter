// ws_service.dart — Cliente WebSocket com reconexão automática

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models.dart';

const _wsUrl = 'ws://localhost:8765';
const _reconnectDelay = Duration(seconds: 3);

enum WsStatus { disconnected, connecting, connected }

enum FilterMode { all, party, target }

class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  WsStatus _status = WsStatus.disconnected;
  DpsSnapshot _snapshot = DpsSnapshot.empty();
  FilterMode _filterMode = FilterMode.all;
  String? _error;

  WsStatus get status      => _status;
  DpsSnapshot get snapshot => _snapshot;
  FilterMode get filterMode => _filterMode;
  String? get error        => _error;
  bool get isConnected     => _status == WsStatus.connected;

  void connect() {
    if (_status == WsStatus.connecting || _status == WsStatus.connected) return;
    _setStatus(WsStatus.connecting);
    _tryConnect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _setStatus(WsStatus.disconnected);
  }

  void sendReset() {
    _send({'action': 'reset'});
  }

  void sendFilter(FilterMode mode) {
    if (_filterMode == mode) return;
    _filterMode = mode;
    _send({'action': 'set_filter', 'mode': mode.name});
    notifyListeners();
  }

  void _tryConnect() {
    _sub?.cancel();
    _sub = null;
    try { _channel?.sink.close(); } catch (_) {}

    try {
      final uri = Uri.parse(_wsUrl);
      _channel = WebSocketChannel.connect(uri);

      // Aguarda handshake real antes de marcar conectado
      _channel!.ready.then((_) {
        if (_status == WsStatus.connecting) {
          _error = null;
          _setStatus(WsStatus.connected);
        }
      }, onError: _onError);

      _sub = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true, // impede onError + onDone dispararem juntos
      );
    } catch (e) {
      _onError(e);
    }
  }

  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'snapshot') {
        _snapshot = DpsSnapshot.fromJson(json['data'] as Map<String, dynamic>);
        notifyListeners();
      } else if (type == 'reset_ack') {
        _snapshot = DpsSnapshot.empty();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('WsService parse error: $e');
    }
  }

  void _onError(dynamic error) {
    if (_status == WsStatus.disconnected) return;
    _error = error.toString();
    _sub?.cancel();
    _sub = null;
    _setStatus(WsStatus.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_status == WsStatus.disconnected) return;
    _sub?.cancel();
    _sub = null;
    _setStatus(WsStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_status == WsStatus.disconnected) {
        _setStatus(WsStatus.connecting);
        _tryConnect();
      }
    });
  }

  void _send(Map<String, dynamic> payload) {
    if (!isConnected) return;
    _channel?.sink.add(jsonEncode(payload));
  }

  void _setStatus(WsStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}