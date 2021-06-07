import 'dart:html';
import 'dart:async';
import 'websocket_impl.dart';

class _WebSocketHtml implements WebsocketImpl {
  bool _expired = false; //是否已废弃
  WebSocket? _socket; //套接字实例
  StreamSubscription? _subscriptionOnOpen;
  StreamSubscription? _subscriptionOnMessage;
  StreamSubscription? _subscriptionOnClose;
  StreamSubscription? _subscriptionOnError;

  @override
  void add(data) {
    if (_socket != null) {
      _socket!.send(data);
    }
  }

  @override
  void close([int? code, String? reason]) {
    _expired = true;
    if (_subscriptionOnOpen != null) {
      _subscriptionOnOpen!.cancel();
      _subscriptionOnOpen = null;
    }
    if (_subscriptionOnMessage != null) {
      _subscriptionOnMessage!.cancel();
      _subscriptionOnMessage = null;
    }
    if (_subscriptionOnClose != null) {
      _subscriptionOnClose!.cancel();
      _subscriptionOnClose = null;
    }
    if (_subscriptionOnError != null) {
      _subscriptionOnError!.cancel();
      _subscriptionOnError = null;
    }
    if (_socket != null) {
      _socket!.close(code, reason);
      _socket = null;
    }
  }

  @override
  void connect(String url, {WebsocketImplOnOpen? onOpen, WebsocketImplOnMessage? onMessage, WebsocketImplOnClose? onClose, WebsocketImplOnError? onError}) {
    if (_expired) return;
    _socket = WebSocket(url);
    _socket!.binaryType = 'arraybuffer';
    _subscriptionOnOpen = _socket!.onOpen.listen((event) {
      if (onOpen != null) onOpen();
    });
    _subscriptionOnMessage = _socket!.onMessage.listen((event) {
      if (onMessage != null) onMessage(event.data);
    });
    _subscriptionOnClose = _socket!.onClose.listen((event) {
      if (onClose != null) onClose(event.code, event.reason);
    });
    _subscriptionOnError = _socket!.onError.listen((event) {
      if (onError != null) onError(event);
    });
  }

  @override
  bool isConnected() => _socket != null && _socket!.readyState == WebSocket.OPEN;

  @override
  bool isNative() => false;
}

WebsocketImpl createWebSocket() {
  return _WebSocketHtml();
}
