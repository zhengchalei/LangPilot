import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';

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
  DesktopLocalModelManager({http.Client? client, Directory? cacheRoot})
    : _client = client ?? http.Client(),
      _cacheRootOverride = cacheRoot;

  final http.Client _client;
  final Directory? _cacheRootOverride;

  @override
  Future<LocalModelStatus> getStatus(LocalModelDefinition model) async {
    final directory = _modelDirectory(model);
    final modelFile = model.hasDownloadArtifact
        ? _downloadedModelFile(model)
        : null;
    final isDownloaded = modelFile != null && await modelFile.exists();

    return LocalModelStatus(
      model: model,
      packaging: LocalModelPackaging.desktop,
      canDownload: model.hasDownloadArtifact,
      isDownloaded: isDownloaded,
      canRunInference: model.hasDownloadArtifact,
      localPath: modelFile?.path ?? directory.path,
      message: _statusMessage(
        model: model,
        isDownloaded: isDownloaded,
        localPath: modelFile?.path,
      ),
    );
  }

  @override
  Future<LocalModelStatus> downloadModel(
    LocalModelDefinition model, {
    String? accessToken,
    LocalModelDownloadProgressCallback? onProgress,
  }) async {
    if (!model.hasDownloadArtifact) {
      throw LocalModelException(_statusMessage(model: model));
    }
    final normalizedAccessToken = accessToken?.trim() ?? '';
    if (model.requiresDownloadToken && normalizedAccessToken.isEmpty) {
      throw LocalModelException(
        '${model.displayName} 的 GGUF 文件需要 Hugging Face 访问令牌。请在本地模型设置中填写令牌后再下载。',
      );
    }

    final directory = _modelDirectory(model);
    await directory.create(recursive: true);

    final file = await _resolveDownloadFile(
      model,
      accessToken: normalizedAccessToken,
    );

    var downloadedBytes = 0;
    await _downloadFile(
      repositoryId: model.downloadRepositoryId!,
      remotePath: file.path,
      target: _downloadedModelFile(model),
      accessToken: normalizedAccessToken,
      onChunk: (chunkBytes) {
        downloadedBytes += chunkBytes;
        onProgress?.call(
          LocalModelDownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: file.size,
            currentFile: file.path,
          ),
        );
      },
    );

    final manifest = File(_join(directory.path, 'langpilot-model.json'));
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'modelId': model.id,
        'sourceRepositoryId': model.repositoryId,
        'downloadRepositoryId': model.downloadRepositoryId,
        'downloadFileName': model.downloadFileName,
        'downloadedAt': DateTime.now().toUtc().toIso8601String(),
        'files': [
          {'path': file.path, 'size': file.size},
        ],
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
    if (!status.canRunInference) {
      throw LocalModelException(status.message);
    }
    if (!status.isDownloaded) {
      throw LocalModelException(
        '请先在模型设置中下载 ${status.model.displayName}。${status.message}',
      );
    }

    final modelFile = _downloadedModelFile(status.model);
    return _runLocalCorrection(modelFile: modelFile, text: text);
  }

  Future<_RepositoryFile> _resolveDownloadFile(
    LocalModelDefinition model, {
    required String accessToken,
  }) async {
    final uri = Uri.https(
      'huggingface.co',
      '/api/models/${model.downloadRepositoryId}/tree/main',
      {'recursive': 'true'},
    );
    final response = await _client
        .get(uri, headers: _authorizationHeaders(accessToken))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw LocalModelException(
          '无法读取 ${model.displayName} 的 Hugging Face 文件列表：访问令牌无效、缺失权限，或模型仓库需要先接受访问条件。',
        );
      }
      throw LocalModelException(
        '无法读取 Hugging Face 模型文件列表：HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const LocalModelException('Hugging Face 模型文件列表格式不可识别。');
    }

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      if (item['type'] == 'directory') {
        continue;
      }
      final path = item['path'];
      if (path != model.downloadFileName) {
        continue;
      }
      return _RepositoryFile(path: path as String, size: _fileSize(item));
    }

    throw LocalModelException(
      '没有在 ${model.downloadRepositoryId} 找到 ${model.downloadFileName}。',
    );
  }

  Future<void> _downloadFile({
    required String repositoryId,
    required String remotePath,
    required File target,
    required String accessToken,
    required void Function(int bytes) onChunk,
  }) async {
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.download');
    final request = http.Request(
      'GET',
      Uri.parse(
        'https://huggingface.co/$repositoryId/resolve/main/${_encodeRemotePath(remotePath)}',
      ),
    );
    request.headers.addAll(_authorizationHeaders(accessToken));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw LocalModelException(
          '下载 $remotePath 失败：Hugging Face 访问令牌无效、缺失权限，或模型仓库需要先接受访问条件。',
        );
      }
      throw LocalModelException(
        '下载 $remotePath 失败：HTTP ${response.statusCode}',
      );
    }

    final sink = temp.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        onChunk(chunk.length);
      }
    } finally {
      await sink.close();
    }
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }

  Future<CorrectionResult> _runLocalCorrection({
    required File modelFile,
    required String text,
  }) async {
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 0),
      );
      final session = ChatSession(engine, systemPrompt: _systemPrompt);
      final prompt = jsonEncode({
        'input': text.trim(),
        'containsChinese': _containsCjk(text),
        'maxSuggestions': 3,
      });

      final buffer = StringBuffer();
      await for (final chunk in session.create(
        [LlamaTextContent(prompt)],
        params: const GenerationParams(
          maxTokens: 1024,
          temp: 0.2,
          topP: 0.9,
          topK: 40,
          stopSequences: ['<|im_end|>'],
        ),
        enableThinking: false,
      )) {
        if (chunk.choices.isEmpty) {
          continue;
        }
        final content = chunk.choices.first.delta.content;
        if (content != null) {
          buffer.write(content);
        }
      }

      return _parseGeneratedResult(buffer.toString());
    } on FormatException catch (error) {
      throw LocalModelException('本地模型返回格式不是有效 JSON：${error.message}');
    } on LlamaException catch (error) {
      throw LocalModelException('本地 Qwen 推理失败：$error');
    } finally {
      await engine.dispose();
    }
  }

  Directory _modelDirectory(LocalModelDefinition model) {
    return Directory(_join(_cacheRoot().path, _safeDirectoryName(model.id)));
  }

  File _downloadedModelFile(LocalModelDefinition model) {
    return File(_join(_modelDirectory(model).path, model.downloadFileName!));
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

  int? _fileSize(Map<String, dynamic> item) {
    final size = item['size'];
    if (size is int) {
      return size;
    }
    final lfs = item['lfs'];
    if (lfs is Map && lfs['size'] is int) {
      return lfs['size'] as int;
    }
    return null;
  }

  String _safeDirectoryName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  String _encodeRemotePath(String path) {
    return path.split('/').map(Uri.encodeComponent).join('/');
  }

  Map<String, String> _authorizationHeaders(String accessToken) {
    if (accessToken.isEmpty) {
      return const {};
    }
    return {'authorization': 'Bearer $accessToken'};
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
    if (!model.hasDownloadArtifact) {
      return '${model.repositoryId} 当前没有公开可用的 GGUF 本地运行文件；Desktop 不能下载或离线运行这个模型，请选择 Qwen/Qwen3.5-2B 或使用在线模型。';
    }
    if (isDownloaded) {
      return 'Desktop 已下载 ${model.displayName} 的 GGUF 本地运行文件，可以离线纠错。文件：$localPath';
    }
    if (model.requiresDownloadToken) {
      return 'Desktop 可下载 ${model.displayName} 的 GGUF 文件并用内置运行时离线纠错；该文件需要 Hugging Face 访问令牌。来源：${model.downloadRepositoryId}/${model.downloadFileName}。';
    }
    return 'Desktop 可下载 ${model.displayName} 的 Q4_K_M GGUF 文件并用内置运行时离线纠错。来源：${model.downloadRepositoryId}/${model.downloadFileName}。';
  }

  bool _containsCjk(String text) {
    for (final codePoint in text.runes) {
      if (codePoint >= 0x4e00 && codePoint <= 0x9fff) {
        return true;
      }
    }
    return false;
  }

  CorrectionResult _parseGeneratedResult(String content) {
    final decoded = jsonDecode(_extractJsonObject(content));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('推荐结果不是对象');
    }
    return CorrectionResult.fromJson(decoded);
  }

  String _extractJsonObject(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) {
      throw const FormatException('找不到 JSON 对象');
    }
    return trimmed.substring(firstBrace, lastBrace + 1);
  }

  static const _systemPrompt = '''
You are LangPilot, an English writing correction assistant for Chinese-speaking users.
Return only valid JSON and no markdown.

JSON schema:
{
  "isAlreadyCorrect": boolean,
  "suggestions": [
    {
      "title": "Natural correction",
      "english": "Corrected or improved English text.",
      "chineseExplanation": "简洁中文解释，说明语法、词汇、语气或翻译处理。",
      "changes": ["短中文修改点"]
    }
  ]
}

Rules:
- Produce 1 to 3 suggestions.
- If the input is already grammatically correct, set isAlreadyCorrect to true and include at most one more natural expression.
- If the input contains Chinese, translate the Chinese meaning naturally into the English result instead of leaving Chinese placeholders.
- Preserve the user's core meaning, paragraph structure, names, numbers, and technical terms.
- Keep explanations concise and useful for learning grammar and vocabulary.
''';
}

class _RepositoryFile {
  const _RepositoryFile({required this.path, required this.size});

  final String path;
  final int? size;
}
