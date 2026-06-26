import 'model_settings.dart';

class LocalModelDefinition {
  const LocalModelDefinition({
    required this.id,
    required this.displayName,
    required this.repositoryId,
    required this.sizeLabel,
    required this.description,
    required this.storageLabel,
    required this.resourceLabel,
  });

  final String id;
  final String displayName;
  final String repositoryId;
  final String sizeLabel;
  final String description;
  final String storageLabel;
  final String resourceLabel;

  String get modelScopeCommand => 'modelscope download --model $repositoryId';
}

const localQwenModels = <LocalModelDefinition>[
  LocalModelDefinition(
    id: 'Qwen/Qwen3.5-0.5B',
    displayName: 'Qwen 3.5 0.5B',
    repositoryId: 'Qwen/Qwen3.5-0.5B',
    sizeLabel: '约 0.5B 参数',
    description: '最省资源，适合轻量纠错和移动端备选；复杂长文本质量较弱。',
    storageLabel: '约 1-2 GB 存储',
    resourceLabel: '建议 4 GB+ 内存，CPU 可跑，移动端需原生推理运行时。',
  ),
  LocalModelDefinition(
    id: 'Qwen/Qwen3.5-0.8B',
    displayName: 'Qwen 3.5 0.8B',
    repositoryId: 'Qwen/Qwen3.5-0.8B',
    sizeLabel: '约 0.8B 参数',
    description: '体积和质量折中，默认推荐给普通客户端。',
    storageLabel: '约 2-4 GB 存储',
    resourceLabel: '建议 6 GB+ 内存，CPU 可跑但会慢，移动端建议中高端设备。',
  ),
  LocalModelDefinition(
    id: 'Qwen/Qwen3.5-2B',
    displayName: 'Qwen 3.5 2B',
    repositoryId: 'Qwen/Qwen3.5-2B',
    sizeLabel: '约 2B 参数',
    description: '质量更高，适合桌面客户端；下载、内存和耗时都更高。',
    storageLabel: '约 5-8 GB 存储',
    resourceLabel: '建议 8-12 GB+ 内存；移动端只建议高端设备或量化后使用。',
  ),
];

LocalModelDefinition localModelById(String id) {
  for (final model in localQwenModels) {
    if (model.id == id) {
      return model;
    }
  }
  return localQwenModels.firstWhere(
    (model) => model.id == ModelSettings.defaultLocalModelId,
  );
}
