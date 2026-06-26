import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langpilot/models/local_model_catalog.dart';
import 'package:langpilot/services/local_model_manager_io.dart';

void main() {
  test('catalog exposes Qwen 0.5B, 0.8B, and 2B choices', () {
    expect(localQwenModels.map((model) => model.id), [
      'Qwen/Qwen3.5-0.5B',
      'Qwen/Qwen3.5-0.8B',
      'Qwen/Qwen3.5-2B',
    ]);
  });

  test('desktop manager downloads with ModelScope CLI', () async {
    final tempDir = await Directory.systemTemp.createTemp('langpilot-models-');
    addTearDown(() => tempDir.delete(recursive: true));
    final calls = <List<String>>[];

    final manager = DesktopLocalModelManager(
      cacheRoot: tempDir,
      runProcess: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(1, 0, 'ok', '');
      },
    );

    final status = await manager.downloadModel(
      localModelById('Qwen/Qwen3.5-0.8B'),
    );

    expect(calls.single.take(4), [
      'modelscope',
      'download',
      '--model',
      'Qwen/Qwen3.5-0.8B',
    ]);
    expect(calls.single, contains('--local_dir'));
    expect(status.isDownloaded, isTrue);
    expect(status.canRunInference, isFalse);
    expect(
      await File('${status.localPath}/langpilot-model.json').exists(),
      isTrue,
    );
  });

  test('desktop manager explains missing ModelScope CLI', () async {
    final tempDir = await Directory.systemTemp.createTemp('langpilot-models-');
    addTearDown(() => tempDir.delete(recursive: true));
    final manager = DesktopLocalModelManager(
      cacheRoot: tempDir,
      runProcess: (executable, arguments) {
        throw const ProcessException('modelscope', [], '没有那个文件或目录');
      },
    );

    expect(
      () => manager.downloadModel(localModelById('Qwen/Qwen3.5-0.5B')),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('pip install modelscope'),
        ),
      ),
    );
  });
}
