///
/// WebsocketImpl
///
typedef WebsocketImplOnOpen = void Function();
typedef WebsocketImplOnMessage = void Function(dynamic data);
typedef WebsocketImplOnClose = void Function(int? code, String? reason);
typedef WebsocketImplOnError = void Function(dynamic e);

abstract class WebsocketImpl {
  void connect(String url, {WebsocketImplOnOpen? onOpen, WebsocketImplOnMessage? onMessage, WebsocketImplOnClose? onClose, WebsocketImplOnError? onError});
  void add(dynamic data);
  void close([int? code, String? reason]);
  bool isConnected();
  bool isNative();
}
