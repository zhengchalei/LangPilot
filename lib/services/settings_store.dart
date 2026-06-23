import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_settings.dart';

abstract interface class SettingsStore {
  Future<ModelSettings> load();

  Future<void> save(ModelSettings settings);
}

class LocalSettingsStore implements SettingsStore {
  LocalSettingsStore({Future<SharedPreferences>? preferences})
    : _preferencesFuture = preferences;

  static const _baseUrlKey = 'model.base_url';
  static const _modelKey = 'model.name';
  static const _apiKeyKey = 'model.api_key';

  Future<SharedPreferences>? _preferencesFuture;

  Future<SharedPreferences> get _preferences =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  @override
  Future<ModelSettings> load() async {
    final preferences = await _preferences;

    return ModelSettings(
      baseUrl: preferences.getString(_baseUrlKey) ?? '',
      apiKey: preferences.getString(_apiKeyKey) ?? '',
      model: preferences.getString(_modelKey) ?? 'deepseek-chat',
    );
  }

  @override
  Future<void> save(ModelSettings settings) async {
    final preferences = await _preferences;
    await preferences.setString(_baseUrlKey, settings.baseUrl.trim());
    await preferences.setString(_modelKey, settings.model.trim());

    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      await preferences.remove(_apiKeyKey);
    } else {
      await preferences.setString(_apiKeyKey, apiKey);
    }
  }
}
