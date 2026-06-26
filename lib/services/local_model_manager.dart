import '../models/correction_result.dart';
import '../models/local_model_catalog.dart';
import '../models/model_settings.dart';

typedef LocalModelDownloadProgressCallback =
    void Function(LocalModelDownloadProgress progress);

enum LocalModelPackaging {
  web('Web'),
  desktop('Desktop'),
  app('App');

  const LocalModelPackaging(this.label);

  final String label;
}

class LocalModelDownloadProgress {
  const LocalModelDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.currentFile,
  });

  final int downloadedBytes;
  final int? totalBytes;
  final String currentFile;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (downloadedBytes / total).clamp(0, 1).toDouble();
  }
}

class LocalModelStatus {
  const LocalModelStatus({
    required this.model,
    required this.packaging,
    required this.canDownload,
    required this.isDownloaded,
    required this.canRunInference,
    required this.message,
    this.localPath,
  });

  final LocalModelDefinition model;
  final LocalModelPackaging packaging;
  final bool canDownload;
  final bool isDownloaded;
  final bool canRunInference;
  final String message;
  final String? localPath;

  bool get isReady => isDownloaded && canRunInference;
}

class LocalModelException implements Exception {
  const LocalModelException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class LocalModelManager {
  Future<LocalModelStatus> getStatus(LocalModelDefinition model);

  Future<LocalModelStatus> downloadModel(
    LocalModelDefinition model, {
    String? accessToken,
    LocalModelDownloadProgressCallback? onProgress,
  });

  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  });
}

class UnsupportedLocalModelManager implements LocalModelManager {
  const UnsupportedLocalModelManager(this.packaging);

  final LocalModelPackaging packaging;

  @override
  Future<LocalModelStatus> getStatus(LocalModelDefinition model) async {
    return LocalModelStatus(
      model: model,
      packaging: packaging,
      canDownload: false,
      isDownloaded: false,
      canRunInference: false,
      message: _unsupportedMessage(packaging),
    );
  }

  @override
  Future<LocalModelStatus> downloadModel(
    LocalModelDefinition model, {
    String? accessToken,
    LocalModelDownloadProgressCallback? onProgress,
  }) async {
    final status = await getStatus(model);
    throw LocalModelException(status.message);
  }

  @override
  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  }) async {
    final status = await getStatus(localModelById(settings.localModelId));
    throw LocalModelException(status.message);
  }

  static String _unsupportedMessage(LocalModelPackaging packaging) {
    switch (packaging) {
      case LocalModelPackaging.web:
        return 'Web 打包不支持在端内执行 ModelScope 下载或本地推理，请使用在线模型。';
      case LocalModelPackaging.desktop:
        return 'Desktop 打包不支持当前本地模型，请先确认已安装 ModelScope CLI。';
      case LocalModelPackaging.app:
        return 'App 打包不支持在端内执行 ModelScope CLI；移动端需要接入原生推理运行时后才能离线使用。';
    }
  }
}
