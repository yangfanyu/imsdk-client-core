import 'package:imsdk_client_core/src/processor_impl.dart';

class _ProcessorHtml implements ProcessorImpl {
  int _taskIdInc = 0;
  ProcessorHandler? _processorHandler;

  @override
  Future<bool> start(ProcessorHandler processorHandler) {
    if (_processorHandler == null) {
      _processorHandler = processorHandler;
      return Future.value(true);
    } else {
      return Future.value(false);
    }
  }

  @override
  Future<T?> runTask<T>(String taskType, dynamic taskData) {
    if (_processorHandler == null) return Future.value(null);
    final taskId = _taskIdInc++;
    final message = ProcessorMessage(taskType, taskId, taskData);
    if (_processorHandler!.debug) print('_ProcessorIO handle task ${message.type} ${message.id} ${message.data}');
    dynamic result;
    try {
      if (message.type.startsWith('\$') && message.type.endsWith('\$')) {
        result = _processorHandler!.bridgeHandle(message);
      } else {
        result = _processorHandler!.customHandle(message);
      }
    } catch (e) {
      result = null;
    }
    return Future.value(result);
  }

  @override
  void destroy() {
    _processorHandler = null;
  }
}

ProcessorImpl createProcessor() {
  return _ProcessorHtml();
}
