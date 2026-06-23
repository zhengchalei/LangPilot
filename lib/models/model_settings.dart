class ModelSettings {
  const ModelSettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = 'deepseek-chat',
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  ModelSettings copyWith({String? baseUrl, String? apiKey, String? model}) {
    return ModelSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}
