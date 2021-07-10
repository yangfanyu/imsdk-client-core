///
/// ProcessorImpl
///
import 'dart:async';

abstract class ProcessorImpl {
  Future<bool> start(ProcessorHandler processorHandler);
  Future<T?> runTask<T>(String taskType, dynamic taskData);
  void destroy();
}

class ProcessorTask<T> {
  final int time; //请求的时间
  final Completer<T> completer;
  ProcessorTask(this.completer) : time = DateTime.now().millisecondsSinceEpoch;
}

typedef ProcessorHandle = dynamic Function(ProcessorMessage message);

class ProcessorHandler {
  dynamic sendPort;
  final bool debug; //是否打印任务处理日志
  final int timeout; //任务处理超时时间（毫秒）
  final ProcessorHandle bridgeHandle; //保留的任务处理器（顶级函数 或 静态函数）
  final ProcessorHandle customHandle; //自定义任务处理器（顶级函数 或 静态函数）
  ProcessorHandler({
    this.sendPort = null,
    this.debug = false,
    this.timeout = 3000,
    required this.bridgeHandle,
    required this.customHandle,
  });
}

class ProcessorMessage {
  final String type;
  final int id;
  final dynamic data;
  ProcessorMessage(this.type, this.id, this.data);
}
