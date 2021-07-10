import 'package:imsdk_client_core/src/processor_impl.dart';

class _ProcessAPI implements ProcessorImpl {
  @override
  Future<bool> start(ProcessorHandler processorHandler) {
    throw UnimplementedError();
  }

  @override
  Future<T?> runTask<T>(String taskType, taskData) {
    throw UnimplementedError();
  }

  @override
  void destroy() {
    throw UnimplementedError();
  }
}

ProcessorImpl createProcessor() {
  return _ProcessAPI();
}
