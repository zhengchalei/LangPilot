import 'package:flutter/foundation.dart';

import 'models/correction_result.dart';
import 'models/model_settings.dart';
import 'services/correction_service.dart';
import 'services/settings_store.dart';

class LangPilotController extends ChangeNotifier {
  LangPilotController({
    required this.correctionClient,
    required this.settingsStore,
  });

  final CorrectionClient correctionClient;
  final SettingsStore settingsStore;

  ModelSettings _settings = const ModelSettings();
  CorrectionResult? _result;
  String? _errorMessage;
  String? _infoMessage;
  bool _isLoadingSettings = false;
  bool _isChecking = false;
  bool _isSavingSettings = false;

  ModelSettings get settings => _settings;
  CorrectionResult? get result => _result;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  bool get isLoadingSettings => _isLoadingSettings;
  bool get isChecking => _isChecking;
  bool get isSavingSettings => _isSavingSettings;

  Future<void> loadSettings() async {
    _isLoadingSettings = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await settingsStore.load();
    } catch (error) {
      _errorMessage = '读取本地模型设置失败：$error';
    } finally {
      _isLoadingSettings = false;
      notifyListeners();
    }
  }

  Future<void> saveSettings(ModelSettings settings) async {
    _isSavingSettings = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await settingsStore.save(settings);
      _settings = settings;
      _infoMessage = '模型设置已保存。';
    } catch (error) {
      _errorMessage = '保存模型设置失败：$error';
      rethrow;
    } finally {
      _isSavingSettings = false;
      notifyListeners();
    }
  }

  Future<void> correctText(
    String text, {
    CorrectionResult Function(CorrectionResult result)? transformResult,
    String? infoMessage,
  }) async {
    _isChecking = true;
    _errorMessage = null;
    _infoMessage = null;
    _result = null;
    notifyListeners();

    try {
      final result = await correctionClient.correctText(
        text: text,
        settings: _settings,
      );
      _result = transformResult == null ? result : transformResult(result);
      _infoMessage = infoMessage;
    } on CorrectionException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = '纠错失败：$error';
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  void applyLocalResult(CorrectionResult result, {String? infoMessage}) {
    _isChecking = false;
    _errorMessage = null;
    _infoMessage = infoMessage;
    _result = result;
    notifyListeners();
  }

  Future<void> testSettings(ModelSettings settings) async {
    await correctionClient.correctText(
      text: 'I has a useful idea for learning English.',
      settings: settings,
    );
  }
}
