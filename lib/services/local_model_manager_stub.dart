import 'local_model_manager.dart';

LocalModelManager createLocalModelManager() {
  return const UnsupportedLocalModelManager(LocalModelPackaging.web);
}
