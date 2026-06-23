import 'model_settings.dart';

class LocalModelDefinition {
  const LocalModelDefinition({
    required this.id,
    required this.displayName,
    required this.repositoryId,
    required this.sizeLabel,
    required this.description,
    this.downloadRepositoryId,
    this.downloadFileName,
    this.requiresDownloadToken = false,
  });

  final String id;
  final String displayName;
  final String repositoryId;
  final String sizeLabel;
  final String description;
  final String? downloadRepositoryId;
  final String? downloadFileName;
  final bool requiresDownloadToken;

  bool get hasDownloadArtifact =>
      downloadRepositoryId != null && downloadFileName != null;
}

const localQwenModels = <LocalModelDefinition>[
  LocalModelDefinition(
    id: 'Qwen/Qwen3.5-0.5B',
    displayName: 'Qwen 3.5 0.5B',
    repositoryId: 'Qwen/Qwen3.5-0.5B',
    sizeLabel: '约 0.5B 参数',
    description: '更小，下载和启动成本低；GGUF 下载需要 Hugging Face 访问令牌。',
    downloadRepositoryId: 'unsloth/Qwen3.5-0.5B-GGUF',
    downloadFileName: 'Qwen3.5-0.5B-UD-Q4_K_XL.gguf',
    requiresDownloadToken: true,
  ),
  LocalModelDefinition(
    id: 'Qwen/Qwen3.5-2B',
    displayName: 'Qwen 3.5 2B',
    repositoryId: 'Qwen/Qwen3.5-2B',
    sizeLabel: '约 2B 参数',
    description: '质量更高，但下载体积、内存和推理耗时更高。',
    downloadRepositoryId: 'unsloth/Qwen3.5-2B-GGUF',
    downloadFileName: 'Qwen3.5-2B-Q4_K_M.gguf',
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
