/**
 * WssServer的客户端
 */
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'src/websocket_impl.dart';
import 'src/websocket_api.dart' if (dart.library.io) 'src/websocket_io.dart' if (dart.library.html) 'src/websocket_html.dart' as platform;

typedef WssBridgeListenerDecoder = dynamic Function(WssBridgePackData packData);
typedef WssBridgeListenerCallback = void Function(dynamic message, List<dynamic>? params);
typedef WssBridgeRequestCallback = void Function(WssBridgeResponse resp, List<dynamic>? params);
typedef WssBridgeOnopen = void Function(List<dynamic>? params);
typedef WssBridgeOnclose = void Function(int code, String reason, List<dynamic>? params);
typedef WssBridgeOnerror = void Function(String error, List<dynamic>? params);
typedef WssBridgeOnretry = void Function(int count, List<dynamic>? params);
typedef WssBridgeOnsecond = void Function(int second, int delay, List<dynamic>? params);

class WssBridgePackData {
  /**
   * 路由
   */
  static const ROUTE_HEARTICK = '\$heartick\$'; //心跳包路由
  static const ROUTE_RESPONSE = '\$response\$'; //响应请求路由
  /**
   * 状态
   * 
   * 本框架保留状态码:
   * 
   * * 4001-4100 服务端保留状态码范围
   * * 4101-4200 客户端保留状态码范围
   * * 4201-4999 可自定义的状态码范围
   */
  static const CODE_RETRY = {'code': 4101, 'data': 'retry'};
  static const CODE_CLOSE = {'code': 4102, 'data': 'close'};
  static const CODE_ERROR = {'code': 4103, 'data': 'error'};
  static const CODE_CALL = {'code': 4104, 'data': 'call'};

  String route;
  int? reqId;
  dynamic message;
  /**
   * * @param route 路由
   * * @param reqId 请求序号
   * * @param message 报文数据
   */
  WssBridgePackData(this.route, this.reqId, this.message);

  static void _copyUint8List(bool swapInt32Endian, Uint8List to, Uint8List from, int toOffset) {
    if (swapInt32Endian) {
      for (int i = 0; i < from.length; i += 4) {
        to[toOffset + i + 0] = from[i + 3];
        to[toOffset + i + 1] = from[i + 2];
        to[toOffset + i + 2] = from[i + 1];
        to[toOffset + i + 3] = from[i + 0];
      }
    } else {
      for (int i = 0; i < from.length; i++) {
        to[toOffset + i] = from[i];
      }
    }
  }

  /**
   * 将数据包进行序列化，采用随机生成iv和key的AES加密算法，CBC、Pkcs7
   * 
   * * @param pack 要序列化的数据包
   * * @param pwd 加密的密码
   * * @param binary 是否返回二进制结果，设置了pwd时生效
   * * @returns String|Uint8List
   */
  static dynamic serialize(WssBridgePackData pack, String? pwd, bool binary) {
    try {
      String str = json.encode(pack);
      if (pwd != null) {
        //ArrayBuffer or base64 string
        Hmac hmacSha256 = Hmac(sha256, utf8.encode(pwd)); // HMAC-SHA256
        Uint8List salt = Key.fromSecureRandom(16).bytes;
        Uint8List iv = Key.fromSecureRandom(16).bytes;
        List<int> key = hmacSha256.convert(salt).bytes;
        Encrypter aesCrypto = Encrypter(AES(Key(key as Uint8List), mode: AESMode.cbc, padding: 'PKCS7'));
        Uint8List body = aesCrypto.encrypt(str, iv: IV(iv)).bytes;
        Uint8List encRes = Uint8List(salt.length + iv.length + body.length);
        _copyUint8List(binary, encRes, salt, 0);
        _copyUint8List(binary, encRes, iv, salt.length);
        _copyUint8List(binary, encRes, body, salt.length + iv.length);
        return binary ? encRes : base64Encode(encRes);
      } else {
        //json string
        return str;
      }
    } catch (e) {
      return null;
    }
  }

  /**
   * 将收到的数据进行反序列化，采用随机生成iv和key的AES解密算法，CBC、Pkcs7
   * 
   * * @param data 要解密的数据
   * * @param pwd 解密的密码
   */
  static WssBridgePackData? deserialize(dynamic data, String? pwd) {
    try {
      if (pwd != null) {
        //ArrayBuffer or base64 string
        Hmac hmacSha256 = Hmac(sha256, utf8.encode(pwd)); // HMAC-SHA256
        Uint8List words;
        if (data is String) {
          words = base64Decode(data);
        } else {
          words = Uint8List(data.length);
          _copyUint8List(true, words, data, 0);
        }
        Uint8List salt = words.sublist(0, 16);
        Uint8List iv = words.sublist(16, 32);
        List<int> key = hmacSha256.convert(salt).bytes;
        Uint8List body = words.sublist(32);
        Encrypter aesCrypto = Encrypter(AES(Key(key as Uint8List), mode: AESMode.cbc, padding: 'PKCS7'));
        String decRes = aesCrypto.decrypt(Encrypted(body), iv: IV(iv));
        Map<String, dynamic> obj = json.decode(decRes);
        return WssBridgePackData(obj['route'], obj['reqId'], obj['message']);
      } else {
        //json string
        Map<String, dynamic> obj = data is String ? json.decode(data) : {};
        return WssBridgePackData(obj['route'], obj['reqId'], obj['message']);
      }
    } catch (e) {
      return null;
    }
  }

  /**
   * 计算md5编码
   * * @param data 要计算编码的字符串
   */
  static String getMd5(String data) {
    return md5.convert(utf8.encode(data)).toString();
  }

  /**
   * 转换为JSON字符串
   */
  Map<String, dynamic> toJson() => {'route': route, 'reqId': reqId, 'message': message};
}

class WssBridgeListener {
  bool once; //是否只触发一次
  WssBridgeListenerCallback? onmessage;
  List<dynamic>? params;

  WssBridgeListener(this.once, this.onmessage, this.params);

  void callMessage(dynamic message) {
    if (onmessage != null) {
      onmessage!(message, params);
    }
  }
}

class WssBridgeRequest {
  int time; //请求的时间
  WssBridgeRequestCallback? onsuccess;
  WssBridgeRequestCallback? onerror;
  List<dynamic>? params;

  WssBridgeRequest(this.onsuccess, this.onerror, this.params) : time = DateTime.now().millisecondsSinceEpoch;

  void callSuccess(WssBridgeResponse resp) {
    if (onsuccess != null) {
      onsuccess!(resp, params);
    }
  }

  void callError(WssBridgeResponse resp) {
    if (onerror != null) {
      onerror!(resp, params);
    }
  }
}

class WssBridgeResponse {
  int code; //状态码
  dynamic data; //正确数据或错误描述

  WssBridgeResponse(this.code, this.data);

  bool get ok => code == 200;
}

class WssBridge {
  static const LOG_LEVEL_ALL = 1;
  static const LOG_LEVEL_DATA = 2;
  static const LOG_LEVEL_INFO = 3;
  static const LOG_LEVEL_NONE = 4;
  String _host; //服务器地址
  String? _pwd; //数据加解密密码
  bool _binary; //是否用二进制传输
  int _timeout; //请求超时（毫秒）
  int _heartick; //心跳间隔（秒）
  int _conntick; //重连间隔（秒）
  Timer? _timer; //秒钟计时器
  int _timerInc; //秒数自增量
  int _reqIdInc; //请求自增量
  int _netDelay; //网络延迟
  int _retryCnt; //断线重连尝试次数
  Map<String, List<WssBridgeListener>> _listeners; //监听集合
  Map<int, WssBridgeRequest> _requests; //请求集合
  int _logLevel; //调试信息输出级别
  WebsocketImpl? _socket; //套接字
  bool _paused; //是否暂停重连
  bool _expired; //是否已经销毁
  //预解码器
  WssBridgeListenerDecoder? _listenerDecoder;
  //状态监听
  WssBridgeOnopen? _onopen;
  WssBridgeOnclose? _onclose;
  WssBridgeOnerror? _onerror;
  WssBridgeOnretry? _onretry;
  WssBridgeOnsecond? _onsecond;
  List<dynamic>? _params;
  /**
   * * @param host 服务器地址（http://、https://、ws://、wss://）
   * * @param pwd 数据加解密密码
   * * @param binary 是否用二进制传输
   * * @param timeout 请求超时（毫秒）
   * * @param heartick 心跳间隔（秒）
   * * @param conntick 重连间隔（秒）
   */
  WssBridge(String host, String? pwd, bool binary, {int timeout = 8000, int heartick = 60, int conntick = 3})
      : _host = host.indexOf('https:') == 0 ? host.replaceFirst('https:', 'wss:') : (host.indexOf('http:') == 0 ? host.replaceFirst('http:', 'ws:') : host),
        _pwd = pwd,
        _binary = binary,
        _timeout = timeout,
        _heartick = heartick,
        _conntick = conntick,
        _timer = null,
        _timerInc = 0,
        _reqIdInc = 0,
        _netDelay = 0,
        _retryCnt = 0,
        _listeners = {},
        _requests = {},
        _logLevel = WssBridge.LOG_LEVEL_NONE,
        _socket = null,
        _paused = false,
        _expired = false;

  void _onSocketOpen() {
    if (_logLevel < WssBridge.LOG_LEVEL_NONE) print('connected $_host');
    _retryCnt = 0; //重置重连次数为0
    if (_onopen != null) _onopen!(_params);
  }

  void _onSocketMessage(dynamic data) {
    if (_expired) return;
    _readPackData(data);
  }

  void _onSocketClose(int? code, String? reason) {
    if (_expired) return;
    _safeClose(WssBridgePackData.CODE_CLOSE['code'] as int, WssBridgePackData.CODE_CLOSE['data'] as String);
    if (_onclose != null) _onclose!(code ?? 0, reason ?? 'Unknow Reason', _params);
  }

  void _onSocketError(dynamic e) {
    if (_expired) return;
    _safeClose(WssBridgePackData.CODE_ERROR['code'] as int, WssBridgePackData.CODE_ERROR['data'] as String);
    if (_onerror != null) _onerror!(e != null ? e.toString() : 'Unknow Error', _params);
  }

  void _onTimerTick() {
    //秒数自增
    _timerInc++;
    //清除超时的请求
    int time = DateTime.now().millisecondsSinceEpoch;
    List<int> list = [];
    _requests.forEach((reqId, request) {
      if (time - request.time > _timeout) {
        request.callError(WssBridgeResponse(504, 'Gateway Timeout'));
        list.add(reqId);
      }
    });
    for (int i = 0; i < list.length; i++) {
      _requests.remove(list[i]);
    }
    //心跳和断线重连
    if (isConnected()) {
      if (_timerInc % _heartick == 0) {
        _sendPackData(WssBridgePackData(WssBridgePackData.ROUTE_HEARTICK, _reqIdInc++, DateTime.now().millisecondsSinceEpoch)); //发送心跳包
      }
    } else {
      if (_timerInc % _conntick == 0 && !_paused) {
        _retryCnt++; //增加重连次数
        if (_onretry != null) _onretry!(_retryCnt, _params);
        _safeOpen(); //安全开启连接
      }
    }
    //秒钟回调
    if (_onsecond != null) {
      _onsecond!(_timerInc, _netDelay, _params);
    }
  }

  void _sendPackData(WssBridgePackData pack) {
    if (_expired) return;
    if (isConnected()) {
      dynamic data = WssBridgePackData.serialize(pack, _pwd, _binary);
      if (data == null) {
        if (_onerror != null) _onerror!('Serialize Error', _params);
        return;
      }
      _socket!.add(data);
      _printPackData('sendPackData >>>', pack);
    }
  }

  void _readPackData(dynamic data) {
    WssBridgePackData? pack = WssBridgePackData.deserialize(data, _pwd);
    if (pack == null) {
      if (_onerror != null) _onerror!('Deserialize Error', _params);
      return;
    }
    _printPackData('readPackData <<<', pack);
    switch (pack.route) {
      case WssBridgePackData.ROUTE_HEARTICK:
        //服务端心跳响应
        _netDelay = DateTime.now().millisecondsSinceEpoch - (pack.message as int); //更新网络延迟
        if (_logLevel == WssBridge.LOG_LEVEL_ALL) print('net delay: ${_netDelay}ms');
        break;
      case WssBridgePackData.ROUTE_RESPONSE:
        //客户端请求响应
        WssBridgeRequest? request = _requests[pack.reqId];
        if (request == null) return; //超时的响应，监听器已经被_timer删除
        _netDelay = DateTime.now().millisecondsSinceEpoch - request.time; //更新网络延迟
        if (_logLevel == WssBridge.LOG_LEVEL_ALL) print('net delay: ${_netDelay}ms');
        dynamic message = pack.message == null ? {} : pack.message;
        WssBridgeResponse resp = WssBridgeResponse(message['code'], message['data']);
        if (resp.ok) {
          request.callSuccess(resp);
        } else {
          request.callError(resp);
        }
        _requests.remove(pack.reqId);
        break;
      default:
        //服务器主动推送
        triggerEvent(pack);
        break;
    }
  }

  void _printPackData(String title, WssBridgePackData pack) {
    if (pack.route == WssBridgePackData.ROUTE_HEARTICK) {
      if (_logLevel == WssBridge.LOG_LEVEL_ALL) {
        print('$title');
        print('\troute: ${pack.route}');
        if (pack.reqId != null) print('\treqId: ${pack.reqId}');
        if (pack.message != null) print('\tmessage: ${pack.message}');
      }
    } else if (_logLevel <= WssBridge.LOG_LEVEL_DATA) {
      print('$title');
      print('\troute: ${pack.route}');
      if (pack.reqId != null) print('\treqId: ${pack.reqId}');
      if (pack.message != null) print('\tmessage: ${pack.message}');
    }
  }

  void _safeOpen() {
    _safeClose(WssBridgePackData.CODE_RETRY['code'] as int, WssBridgePackData.CODE_RETRY['data'] as String); //关闭旧连接
    if (_expired) return;
    _socket = platform.createWebSocket();
    _socket!.connect(_host, onOpen: _onSocketOpen, onMessage: _onSocketMessage, onClose: _onSocketClose, onError: _onSocketError);
  }

  void _safeClose(int code, String reason) {
    if (_socket != null) {
      _socket!.close(code, reason);
      _socket = null;
    }
  }

  /**
   * 开始进行网络连接
   * 
   * * @param onopen 网络连接建立时的回调
   * * @param onclose 网络连接关闭时的回调（包括手动关闭、服务端关闭等情况）
   * * @param onerror 网络连接发生错误时的回调
   * * @param onretry 网络连接断开，自动重连时的回调
   * * @param onsecond 此函数每秒回调一次，回调参数中包含网络延迟等信息
   * * @param context 触发回调函数时的绑定的上下文信息
   * * @param params 触发回调函数时会传回这个参数
   */
  void connect(WssBridgeOnopen? onopen, WssBridgeOnclose? onclose, WssBridgeOnerror? onerror, WssBridgeOnretry? onretry, WssBridgeOnsecond? onsecond, List<dynamic>? params) {
    _onopen = onopen;
    _onclose = onclose;
    _onerror = onerror;
    _onretry = onretry;
    _onsecond = onsecond;
    _params = params;
    //打开
    _safeOpen(); //安全开启连接
    _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) => _onTimerTick());
  }

  /**
   * 强制关闭网络连接，并销毁这个实例
   * 
   * 注意：调用此函数后，此实例不可继续做网络操作，不可重新连接网络。
   */
  void disconnect() {
    if (_logLevel < WssBridge.LOG_LEVEL_NONE) print('disconnected $_host');
    _expired = true;
    //关闭
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
    _safeClose(WssBridgePackData.CODE_CALL['code'] as int, WssBridgePackData.CODE_CALL['data'] as String); //安全关闭连接
  }

  /**
   * 向远程服务器发起请求
   * 
   * * @param route 远程服务器路由地址
   * * @param message 数据包
   * * @param onsuccess 请求成功的回调
   * * @param onerror 请求失败的回调
   * * @param context 触发回调函数时的绑定的上下文信息
   * * @param params 触发回调函数时会传回这个参数
   */
  void request(String route, dynamic message, WssBridgeRequestCallback? onsuccess, WssBridgeRequestCallback? onerror, List<dynamic>? params) {
    int reqId = _reqIdInc++;
    if (onsuccess != null || onerror != null) _requests[reqId] = WssBridgeRequest(onsuccess, onerror, params);
    _sendPackData(WssBridgePackData(route, reqId, message));
  }

  /**
   * 添加指定route的监听器，可用作自由定义事件的管理器
   * 
   * * @param route 网络路由名称、本地自定义事件名称
   * * @param once 是否触发一次后，自动删除此路由
   * * @param onmessage 触发时的回调
   * * @param context 触发回调函数时的绑定的上下文信息
   * * @param params 触发回调函数时会传回这个参数
   */
  void addListener(String route, bool once, WssBridgeListenerCallback? onmessage, List<dynamic>? params) {
    List<WssBridgeListener>? listeners = _listeners[route];
    if (listeners == null) {
      listeners = [];
      _listeners[route] = listeners;
    }
    listeners.add(WssBridgeListener(once, onmessage, params));
  }

  /**
   * 删除指定route的监听器
   * 
   * * @param route 网络路由名称、本地自定义事件名称
   * * @param onmessage 要删除的监听器。不传这个参数则删除route对应的全部路由
   */
  void removeListener(String route, WssBridgeListenerCallback? onmessage) {
    List<WssBridgeListener>? listeners = _listeners[route];
    if (listeners == null) return;
    if (onmessage == null) {
      _listeners.remove(route); //删除该路由的全部监听
    } else {
      List<WssBridgeListener> list = [];
      for (int i = 0; i < listeners.length; i++) {
        WssBridgeListener item = listeners[i];
        if (item.onmessage == onmessage) {
          list.add(item);
        }
      }
      while (list.isNotEmpty) {
        listeners.remove(list.removeLast());
      }
      if (listeners.isEmpty) {
        _listeners.remove(route);
      }
    }
  }

  /**
   * 设置监听器的前置解码器，该解码器将在addListener设置的监听器回调之前调用
   * * @param listenerDecoder 自定义解码器
   */
  void setListenerDecoder(WssBridgeListenerDecoder? listenerDecoder) {
    _listenerDecoder = listenerDecoder;
  }

  /**
   * 手动触发pack.route对应的全部监听器
   * 
   * * @param pack 路由包装实例
   */
  void triggerEvent(WssBridgePackData pack) {
    List<WssBridgeListener>? listeners = _listeners[pack.route];
    if (listeners == null) return;
    List<WssBridgeListener> oncelist = []; //删除只触发一次的监听
    dynamic message = _listenerDecoder == null ? pack.message : _listenerDecoder!(pack);
    for (int i = 0; i < listeners.length; i++) {
      WssBridgeListener item = listeners[i];
      item.callMessage(message);
      if (item.once) {
        oncelist.add(item);
      }
    }
    for (int i = 0; i < oncelist.length; i++) {
      removeListener(pack.route, oncelist[i].onmessage);
    }
  }

  /**
   * 暂停断线自动重连的功能
   */
  void pauseReconnect() => _paused = true;
  /**
   * 恢复断线自动重连的功能
   */
  void resumeReconnect() => _paused = false;

  void setLogLevel(int level) => _logLevel = level;

  int getNetDelay() => _netDelay;

  bool isConnected() => _socket != null && _socket!.isConnected();
}
