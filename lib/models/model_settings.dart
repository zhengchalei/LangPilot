enum ModelProvider {
  online('online'),
  localQwen('local_qwen');

  const ModelProvider(this.value);

  final String value;

  static ModelProvider fromValue(String? value) {
    for (final provider in values) {
      if (provider.value == value) {
        return provider;
      }
    }
    return ModelProvider.online;
  }
}

class ModelSettings {
  const ModelSettings({
    this.provider = ModelProvider.online,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.localModelId = defaultLocalModelId,
    this.localModelAccessToken = '',
    this.autoRecommendDelayMs = defaultAutoRecommendDelayMs,
  });

  static const defaultLocalModelId = 'Qwen/Qwen3.5-2B';
  static const defaultAutoRecommendDelayMs = 2000;
  static const minAutoRecommendDelayMs = 500;
  static const maxAutoRecommendDelayMs = 30000;

  final ModelProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String localModelId;
  final String localModelAccessToken;
  final int autoRecommendDelayMs;

  bool get isOnline => provider == ModelProvider.online;

  bool get isLocalQwen => provider == ModelProvider.localQwen;

  bool get isComplete {
    switch (provider) {
      case ModelProvider.online:
        return baseUrl.trim().isNotEmpty &&
            apiKey.trim().isNotEmpty &&
            model.trim().isNotEmpty;
      case ModelProvider.localQwen:
        return localModelId.trim().isNotEmpty;
    }
  }

  int get effectiveAutoRecommendDelayMs {
    return autoRecommendDelayMs.clamp(
      minAutoRecommendDelayMs,
      maxAutoRecommendDelayMs,
    );
  }

  Duration get autoRecommendDelay {
    return Duration(milliseconds: effectiveAutoRecommendDelayMs);
  }

  String get displayName {
    switch (provider) {
      case ModelProvider.online:
        return model.trim().isEmpty ? '在线模型' : model.trim();
      case ModelProvider.localQwen:
        return localModelId.trim().isEmpty ? '本地 Qwen' : localModelId.trim();
    }
  }

  ModelSettings copyWith({
    ModelProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? localModelId,
    String? localModelAccessToken,
    int? autoRecommendDelayMs,
  }) {
    return ModelSettings(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      localModelId: localModelId ?? this.localModelId,
      localModelAccessToken:
          localModelAccessToken ?? this.localModelAccessToken,
      autoRecommendDelayMs: autoRecommendDelayMs ?? this.autoRecommendDelayMs,
    );
  }
}
