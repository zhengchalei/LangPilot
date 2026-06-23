import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_settings.dart';

abstract interface class SettingsStore {
  Future<ModelSettings> load();

  Future<void> save(ModelSettings settings);
}

class LocalSettingsStore implements SettingsStore {
  LocalSettingsStore({Future<SharedPreferences>? preferences})
    : _preferencesFuture = preferences;

  static const _providerKey = 'model.provider';
  static const _baseUrlKey = 'model.base_url';
  static const _modelKey = 'model.name';
  static const _localModelKey = 'model.local_name';
  static const _localModelTokenKey = 'model.local_access_token';
  static const _apiKeyKey = 'model.api_key';
  static const _autoDelayKey = 'model.auto_recommend_delay_ms';

  Future<SharedPreferences>? _preferencesFuture;

  Future<SharedPreferences> get _preferences =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  @override
  Future<ModelSettings> load() async {
    final preferences = await _preferences;

    return ModelSettings(
      provider: ModelProvider.fromValue(preferences.getString(_providerKey)),
      baseUrl: preferences.getString(_baseUrlKey) ?? '',
      apiKey: preferences.getString(_apiKeyKey) ?? '',
      model: preferences.getString(_modelKey) ?? 'deepseek-chat',
      localModelId:
          preferences.getString(_localModelKey) ??
          ModelSettings.defaultLocalModelId,
      localModelAccessToken: preferences.getString(_localModelTokenKey) ?? '',
      autoRecommendDelayMs:
          preferences.getInt(_autoDelayKey) ??
          ModelSettings.defaultAutoRecommendDelayMs,
    );
  }

  @override
  Future<void> save(ModelSettings settings) async {
    final preferences = await _preferences;
    await preferences.setString(_providerKey, settings.provider.value);
    await preferences.setString(_baseUrlKey, settings.baseUrl.trim());
    await preferences.setString(_modelKey, settings.model.trim());
    await preferences.setString(_localModelKey, settings.localModelId.trim());
    await preferences.setInt(
      _autoDelayKey,
      settings.effectiveAutoRecommendDelayMs,
    );

    final localToken = settings.localModelAccessToken.trim();
    if (localToken.isEmpty) {
      await preferences.remove(_localModelTokenKey);
    } else {
      await preferences.setString(_localModelTokenKey, localToken);
    }

    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      await preferences.remove(_apiKeyKey);
    } else {
      await preferences.setString(_apiKeyKey, apiKey);
    }
  }
}
