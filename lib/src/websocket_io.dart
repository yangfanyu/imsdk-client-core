import 'dart:io';
import 'dart:async';
import 'websocket_impl.dart';

class _WebSocketIO implements WebsocketImpl {
  bool _expired = false; //是否已废弃
  WebSocket? _socket; //套接字实例
  StreamSubscription? _subscription;

  @override
  void add(data) {
    if (_socket != null) {
      _socket!.add(data);
    }
  }

  @override
  void close([int? code, String? reason]) {
    _expired = true;
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }
    if (_socket != null) {
      _socket!.close(code, reason).catchError((e) {});
      _socket = null;
    }
  }

  @override
  void connect(String url, {WebsocketImplOnOpen? onOpen, WebsocketImplOnMessage? onMessage, WebsocketImplOnClose? onClose, WebsocketImplOnError? onError}) {
    if (_expired) return;
    WebSocket.connect(url).then((socket) {
      if (_expired) {
        socket.close(4200, 'expired').catchError((e) {});
      } else {
        _socket = socket;
        _subscription = _socket!.listen((data) {
          if (onMessage != null) onMessage(data);
        }, onDone: () {
          if (onClose != null) onClose(socket.closeCode, socket.closeReason);
        }, onError: (e) {
          if (onError != null) onError(e);
        });
        if (onOpen != null) onOpen(); //在绑定监听器之后调用
      }
    }).catchError((e) {
      if (!_expired) {
        if (onError != null) onError(e);
      }
    });
  }

  @override
  bool isConnected() => _socket != null && _socket!.readyState == WebSocket.open;

  @override
  bool isNative() => true;
}

WebsocketImpl createWebSocket() {
  return _WebSocketIO();
}
