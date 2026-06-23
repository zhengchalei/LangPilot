import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/correction_result.dart';
import '../models/model_settings.dart';
import 'local_model_manager.dart';

abstract interface class CorrectionClient {
  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  });
}

class CorrectionException implements Exception {
  const CorrectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CorrectionService implements CorrectionClient {
  CorrectionService({
    http.Client? client,
    LocalModelManager? localModelManager,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client(),
       _localModelManager =
           localModelManager ??
           const UnsupportedLocalModelManager(LocalModelPackaging.web);

  final http.Client _client;
  final LocalModelManager _localModelManager;
  final Duration timeout;

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

  @override
  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  }) async {
    final input = text.trim();
    if (input.isEmpty) {
      throw const CorrectionException('请输入需要纠错的英文或中英混写内容。');
    }
    if (!settings.isComplete) {
      throw CorrectionException(
        settings.isLocalQwen ? '请先选择本地 Qwen 模型。' : '请先配置模型地址、模型名和 API Key。',
      );
    }

    if (settings.isLocalQwen) {
      try {
        return await _localModelManager.correctText(
          text: input,
          settings: settings,
        );
      } on LocalModelException catch (error) {
        throw CorrectionException(error.message);
      }
    }

    final uri = _chatCompletionsUri(settings.baseUrl);
    final body = jsonEncode({
      'model': settings.model.trim(),
      'temperature': 0.25,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {
          'role': 'user',
          'content': jsonEncode({
            'input': input,
            'containsChinese': _containsCjk(input),
            'maxSuggestions': 3,
          }),
        },
      ],
    });

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const CorrectionException('模型请求超时，请稍后重试或换用更快的模型。');
    } on http.ClientException catch (error) {
      throw CorrectionException('无法连接模型服务：${error.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CorrectionException(_errorMessage(response));
    }

    try {
      return _parseResponse(response.body);
    } on FormatException catch (error) {
      throw CorrectionException('模型返回格式不是有效 JSON：${error.message}');
    }
  }

  void close() {
    _client.close();
  }

  static bool _containsCjk(String text) {
    for (final codePoint in text.runes) {
      if (codePoint >= 0x4e00 && codePoint <= 0x9fff) {
        return true;
      }
    }
    return false;
  }

  static Uri _chatCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    final uri = Uri.parse(trimmed);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const CorrectionException(
        '模型地址需要是完整 URL，例如 https://api.example.com/v1。',
      );
    }

    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    if (path.endsWith('/chat/completions')) {
      return uri;
    }

    final nextPath = path.endsWith('/v1')
        ? '$path/chat/completions'
        : '$path/v1/chat/completions';
    return uri.replace(path: nextPath);
  }

  static CorrectionResult _parseResponse(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('顶层响应不是对象');
    }

    if (decoded.containsKey('suggestions')) {
      return CorrectionResult.fromJson(decoded);
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('缺少 choices');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw const FormatException('choices[0] 不是对象');
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      throw const FormatException('缺少 message');
    }

    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('message.content 为空');
    }

    final resultJson = _extractJsonObject(content);
    final result = jsonDecode(resultJson);
    if (result is! Map<String, dynamic>) {
      throw const FormatException('推荐结果不是对象');
    }

    return CorrectionResult.fromJson(result);
  }

  static String _extractJsonObject(String content) {
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

  static String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return '模型请求失败：${error['message']}';
        }
        if (decoded['message'] != null) {
          return '模型请求失败：${decoded['message']}';
        }
      }
    } on FormatException {
      // Fall through to a compact HTTP status message.
    }
    return '模型请求失败：HTTP ${response.statusCode}';
  }
}
