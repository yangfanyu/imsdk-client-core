import 'dart:async';
import 'dart:isolate';
import 'package:imsdk_client_core/src/processor_impl.dart';

class _ProcessorIO implements ProcessorImpl {
  int _taskIdInc = 0;
  final Map<int, ProcessorTask> _taskMap = {};
  ReceivePort? _receivePort;
  Isolate? _isolate;
  SendPort? _sendPort;
  Timer? _timer; //秒钟计时器

  @override
  Future<bool> start(ProcessorHandler processorHandler) {
    if (_receivePort != null) return Future.value(false);
    final completer = Completer<bool>();
    _receivePort = ReceivePort();
    processorHandler.sendPort = _receivePort!.sendPort;
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete(true);
      } else if (message is ProcessorMessage) {
        final task = _taskMap.remove(message.id);
        if (task != null) task.completer.complete(message.data);
      }
    });
    Isolate.spawn(_entryPoint, processorHandler).then((value) {
      _isolate = value;
      _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) => _onTimerTick(processorHandler.debug, processorHandler.timeout));
    }).catchError((e) {
      destroy();
      completer.complete(false);
    });
    return completer.future;
  }

  @override
  Future<T?> runTask<T>(String taskType, dynamic taskData) {
    if (_sendPort == null) return Future.value(null);
    final taskId = _taskIdInc++;
    final completer = Completer<T>();
    final tasker = ProcessorTask(completer);
    _taskMap[taskId] = tasker;
    _sendPort!.send(ProcessorMessage(taskType, taskId, taskData));
    return tasker.completer.future;
  }

  @override
  void destroy() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
    if (_isolate != null) {
      _isolate!.kill();
      _isolate = null;
    }
    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }
  }

  void _onTimerTick(bool debug, int timeout) {
    if (debug) print('_ProcessorIO _onTimerTick is running... ${_taskMap.keys.toList()}');
    final time = DateTime.now().millisecondsSinceEpoch;
    final list = <int>[];
    _taskMap.forEach((id, task) {
      if (time - task.time > timeout) list.add(id);
    });
    list.forEach((id) {
      final task = _taskMap.remove(id);
      if (task != null) task.completer.complete(null);
    });
  }

  static void _entryPoint(ProcessorHandler processorHandler) {
    final ReceivePort requestReceivePort = ReceivePort();
    final SendPort responseSendPort = processorHandler.sendPort;
    responseSendPort.send(requestReceivePort.sendPort);
    requestReceivePort.listen((message) {
      if (message is ProcessorMessage) {
        if (processorHandler.debug) print('_ProcessorIO handle task ${message.type} ${message.id} ${message.data}');
        dynamic result;
        try {
          if (message.type.startsWith('\$') && message.type.endsWith('\$')) {
            result = processorHandler.bridgeHandle(message);
          } else {
            result = processorHandler.customHandle(message);
          }
        } catch (e) {
          result = null;
        }
        responseSendPort.send(ProcessorMessage(message.type, message.id, result));
      }
    });
  }
}

ProcessorImpl createProcessor() {
  return _ProcessorIO();
}
