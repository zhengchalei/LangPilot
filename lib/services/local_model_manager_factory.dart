import 'local_model_manager.dart';
import 'local_model_manager_stub.dart'
    if (dart.library.io) 'local_model_manager_io.dart'
    as platform;

LocalModelManager createLocalModelManager() {
  return platform.createLocalModelManager();
}
