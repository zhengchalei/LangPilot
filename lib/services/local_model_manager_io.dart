import 'dart:convert';
import 'dart:io';

import '../models/correction_result.dart';
import '../models/local_model_catalog.dart';
import '../models/model_settings.dart';
import 'local_model_manager.dart';

LocalModelManager createLocalModelManager() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return DesktopLocalModelManager();
  }
  return const UnsupportedLocalModelManager(LocalModelPackaging.app);
}

class DesktopLocalModelManager implements LocalModelManager {
  DesktopLocalModelManager({
    Directory? cacheRoot,
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : _cacheRootOverride = cacheRoot,
       _runProcess = runProcess ?? Process.run;

  final Directory? _cacheRootOverride;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  @override
  Future<LocalModelStatus> getStatus(LocalModelDefinition model) async {
    final directory = _modelDirectory(model);
    final isDownloaded = await directory.exists();

    return LocalModelStatus(
      model: model,
      packaging: LocalModelPackaging.desktop,
      canDownload: true,
      isDownloaded: isDownloaded,
      canRunInference: false,
      localPath: directory.path,
      message: _statusMessage(
        model: model,
        isDownloaded: isDownloaded,
        localPath: directory.path,
      ),
    );
  }

  @override
  Future<LocalModelStatus> downloadModel(
    LocalModelDefinition model, {
    String? accessToken,
    LocalModelDownloadProgressCallback? onProgress,
  }) async {
    final directory = _modelDirectory(model);
    await directory.create(recursive: true);

    onProgress?.call(
      LocalModelDownloadProgress(
        downloadedBytes: 0,
        totalBytes: null,
        currentFile: model.repositoryId,
      ),
    );
    late final ProcessResult result;
    try {
      result = await _runProcess('modelscope', [
        'download',
        '--model',
        model.repositoryId,
        '--local_dir',
        directory.path,
      ]);
    } on ProcessException catch (error) {
      throw LocalModelException(
        '没有找到 ModelScope CLI：${error.message}\nLinux 先安装：pip install modelscope\n然后可手动运行：${model.modelScopeCommand}',
      );
    }
    if (result.exitCode != 0) {
      throw LocalModelException(
        'ModelScope 下载失败：${_processOutput(result)}\n请先安装 ModelScope CLI，再运行：${model.modelScopeCommand}',
      );
    }
    onProgress?.call(
      LocalModelDownloadProgress(
        downloadedBytes: 1,
        totalBytes: 1,
        currentFile: model.repositoryId,
      ),
    );

    final manifest = File(_join(directory.path, 'langpilot-model.json'));
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'modelId': model.id,
        'sourceRepositoryId': model.repositoryId,
        'downloadedAt': DateTime.now().toUtc().toIso8601String(),
        'downloadCommand': model.modelScopeCommand,
      }),
    );

    return getStatus(model);
  }

  @override
  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  }) async {
    final status = await getStatus(localModelById(settings.localModelId));
    throw LocalModelException(status.message);
  }

  Directory _modelDirectory(LocalModelDefinition model) {
    return Directory(_join(_cacheRoot().path, _safeDirectoryName(model.id)));
  }

  Directory _cacheRoot() {
    final override = _cacheRootOverride;
    if (override != null) {
      return override;
    }

    final environment = Platform.environment;
    if (Platform.isWindows) {
      final localAppData = environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(_join(localAppData, 'LangPilot\\models'));
      }
    }
    if (Platform.isMacOS) {
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(_join(home, 'Library/Caches/LangPilot/models'));
      }
    }

    final xdgCacheHome = environment['XDG_CACHE_HOME'];
    if (xdgCacheHome != null && xdgCacheHome.isNotEmpty) {
      return Directory(_join(xdgCacheHome, 'langpilot/models'));
    }

    final home = environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(_join(home, '.cache/langpilot/models'));
    }

    return Directory(_join(Directory.systemTemp.path, 'langpilot/models'));
  }

  String _safeDirectoryName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  String _join(String left, String right) {
    if (left.endsWith('/') || left.endsWith(r'\')) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  String _statusMessage({
    required LocalModelDefinition model,
    bool isDownloaded = false,
    String? localPath,
  }) {
    if (isDownloaded) {
      return '已通过 ModelScope 下载 ${model.displayName} 到 $localPath。当前内置推理只支持 GGUF，ModelScope 原始模型需接入移动/桌面原生运行时或转换后才能离线纠错。';
    }
    return '将执行：${model.modelScopeCommand}。${model.storageLabel}；${model.resourceLabel}';
  }

  String _processOutput(ProcessResult result) {
    final output = '${result.stderr}\n${result.stdout}'.trim();
    if (output.isEmpty) {
      return '退出码 ${result.exitCode}';
    }
    return output;
  }
}
