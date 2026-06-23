import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpilot/models/model_settings.dart';
import 'package:langpilot/services/correction_service.dart';

void main() {
  const settings = ModelSettings(
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'secret',
    model: 'flash-model',
  );

  test('posts an OpenAI-compatible request and parses suggestions', () async {
    late http.Request capturedRequest;
    final service = CorrectionService(
      client: MockClient((request) async {
        capturedRequest = request;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'isAlreadyCorrect': false,
                  'suggestions': [
                    {
                      'title': 'Natural correction',
                      'english': 'I have a clear plan.',
                      'chineseExplanation': '修正主谓一致。',
                      'changes': ['主谓一致'],
                    },
                  ],
                }),
              },
            },
          ],
        });
      }),
    );

    final result = await service.correctText(
      text: 'I has 一个 plan.',
      settings: settings,
    );

    expect(
      capturedRequest.url.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(capturedRequest.headers['authorization'], 'Bearer secret');

    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body['model'], 'flash-model');
    expect(body['messages'], isA<List<dynamic>>());
    expect(result.suggestions.single.english, 'I have a clear plan.');
  });

  test('accepts fenced JSON content from a model', () async {
    final service = CorrectionService(
      client: MockClient((request) async {
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': '''
```json
{"isAlreadyCorrect":true,"suggestions":[]}
```
''',
              },
            },
          ],
        });
      }),
    );

    final result = await service.correctText(
      text: 'This sentence is correct.',
      settings: settings,
    );

    expect(result.isAlreadyCorrect, isTrue);
    expect(result.suggestions, isEmpty);
  });

  test('surfaces model error messages', () async {
    final service = CorrectionService(
      client: MockClient((request) async {
        return _jsonResponse({
          'error': {'message': 'invalid api key'},
        }, 401);
      }),
    );

    expect(
      () => service.correctText(text: 'Hello.', settings: settings),
      throwsA(
        isA<CorrectionException>().having(
          (error) => error.message,
          'message',
          contains('invalid api key'),
        ),
      ),
    );
  });
}

http.Response _jsonResponse(Map<String, Object?> body, [int statusCode = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
