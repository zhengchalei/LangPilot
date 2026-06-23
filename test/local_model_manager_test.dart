import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpilot/models/local_model_catalog.dart';
import 'package:langpilot/services/local_model_manager_io.dart';

void main() {
  test(
    'desktop manager downloads the configured Qwen 2B GGUF artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'langpilot-models-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final manager = DesktopLocalModelManager(
        cacheRoot: tempDir,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/tree/main')) {
            return _jsonResponse([
              {'type': 'file', 'path': 'Qwen3.5-2B-Q4_K_M.gguf', 'size': 5},
            ]);
          }

          expect(
            request.url.toString(),
            'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
          );
          return http.Response.bytes([1, 2, 3, 4, 5], 200);
        }),
      );

      final model = localModelById('Qwen/Qwen3.5-2B');
      final status = await manager.downloadModel(model);

      expect(status.canDownload, isTrue);
      expect(status.canRunInference, isTrue);
      expect(status.isDownloaded, isTrue);
      expect(await File(status.localPath!).readAsBytes(), [1, 2, 3, 4, 5]);
    },
  );

  test(
    'desktop manager requires a token for gated Qwen 0.5B artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'langpilot-models-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final manager = DesktopLocalModelManager(cacheRoot: tempDir);
      final model = localModelById('Qwen/Qwen3.5-0.5B');

      final status = await manager.getStatus(model);
      expect(status.canDownload, isTrue);
      expect(status.canRunInference, isTrue);
      expect(status.message, contains('需要 Hugging Face 访问令牌'));

      expect(
        () => manager.downloadModel(model),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('需要 Hugging Face 访问令牌'),
          ),
        ),
      );
    },
  );

  test('desktop manager sends token for gated Qwen 0.5B downloads', () async {
    final tempDir = await Directory.systemTemp.createTemp('langpilot-models-');
    addTearDown(() => tempDir.delete(recursive: true));

    final manager = DesktopLocalModelManager(
      cacheRoot: tempDir,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer hf_secret');
        if (request.url.path.endsWith('/tree/main')) {
          return _jsonResponse([
            {'type': 'file', 'path': 'Qwen3.5-0.5B-UD-Q4_K_XL.gguf', 'size': 3},
          ]);
        }

        expect(
          request.url.toString(),
          'https://huggingface.co/unsloth/Qwen3.5-0.5B-GGUF/resolve/main/Qwen3.5-0.5B-UD-Q4_K_XL.gguf',
        );
        return http.Response.bytes([6, 7, 8], 200);
      }),
    );

    final status = await manager.downloadModel(
      localModelById('Qwen/Qwen3.5-0.5B'),
      accessToken: 'hf_secret',
    );

    expect(status.isDownloaded, isTrue);
    expect(await File(status.localPath!).readAsBytes(), [6, 7, 8]);
  });
}

http.Response _jsonResponse(Object body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
