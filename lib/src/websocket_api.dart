import 'websocket_impl.dart';

class _WebSocketAPI implements WebsocketImpl {
  @override
  void add(data) {
    throw UnimplementedError();
  }

  @override
  void close([int? code, String? reason]) {
    throw UnimplementedError();
  }

  @override
  void connect(String url, {WebsocketImplOnOpen? onOpen, WebsocketImplOnMessage? onMessage, WebsocketImplOnClose? onClose, WebsocketImplOnError? onError}) {
    throw UnimplementedError();
  }

  @override
  bool isConnected() {
    throw UnimplementedError();
  }

  @override
  bool isNative() {
    throw UnimplementedError();
  }
}

WebsocketImpl createWebSocket() {
  return _WebSocketAPI();
}
