import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:langpilot/app_controller.dart';
import 'package:langpilot/main.dart';
import 'package:langpilot/models/correction_result.dart';
import 'package:langpilot/models/model_settings.dart';
import 'package:langpilot/services/correction_service.dart';
import 'package:langpilot/services/settings_store.dart';

void main() {
  testWidgets('renders suggestions and replaces the input', (tester) async {
    final client = _FakeCorrectionClient();
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    await tester.enterText(
      find.byKey(const Key('input_editor')),
      'I has 一个 plan.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('1. Natural correction'), findsOneWidget);
    expect(find.text('I have a clear plan.'), findsOneWidget);
    expect(find.text('增量部分'), findsOneWidget);
    expect(find.text('修改部分'), findsOneWidget);
    expect(find.textContaining('->'), findsWidgets);
    expect(client.callCount, 1);

    await tester.tap(find.byKey(const Key('replace_suggestion_0')));
    await tester.pump(const Duration(milliseconds: 100));

    final textField = tester.widget<TextField>(
      find.byKey(const Key('input_editor')),
    );
    expect(textField.controller?.text, 'I have a clear plan.');
    expect(find.text('已替换到输入框。'), findsWidgets);
  });

  testWidgets('does not submit empty input', (tester) async {
    final client = _FakeCorrectionClient();
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('submit_button')),
    );
    expect(submitButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('input_editor')), 'Hello');
    await tester.pump();

    final enabledSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('submit_button')),
    );
    expect(enabledSubmitButton.onPressed, isNotNull);
    expect(client.callCount, 0);
  });

  testWidgets('marks results stale after editing checked input', (
    tester,
  ) async {
    final controller = LangPilotController(
      correctionClient: _FakeCorrectionClient(),
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    await tester.enterText(
      find.byKey(const Key('input_editor')),
      'I has plan.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('input_editor')),
      'I has plan. More text.',
    );
    await tester.pumpAndSettle();

    expect(find.text('输入已修改，当前推荐来自上一版内容。'), findsOneWidget);
  });

  testWidgets('auto recommends after two seconds without editing', (
    tester,
  ) async {
    final client = _FakeCorrectionClient();
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    await tester.tap(find.byKey(const Key('auto_recommend_switch')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('input_editor')),
      'I has another plan.',
    );
    await tester.pump(const Duration(milliseconds: 1900));

    expect(client.callCount, 0);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(client.callCount, 1);
    expect(find.text('I have a clear plan.'), findsOneWidget);
  });

  testWidgets('auto recommend requests only changed paragraph after baseline', (
    tester,
  ) async {
    final client = _FakeCorrectionClient(
      resultBuilder: (text) => CorrectionResult(
        isAlreadyCorrect: false,
        suggestions: [
          CorrectionSuggestion(
            title: 'Incremental correction',
            english: text.replaceAll('She go home.', 'She goes home.'),
            chineseExplanation: '只修正变化段落。',
            changes: const ['第三人称单数'],
          ),
        ],
      ),
    );
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    const baseline = 'First paragraph.\nShe goes home.\nThird paragraph.';
    await tester.enterText(find.byKey(const Key('input_editor')), baseline);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('auto_recommend_switch')));
    await tester.pump();

    const edited = 'First paragraph.\nShe go home.\nThird paragraph.';
    await tester.enterText(find.byKey(const Key('input_editor')), edited);
    await tester.pump(const Duration(seconds: 2, milliseconds: 50));
    await tester.pumpAndSettle();

    expect(client.requests, hasLength(2));
    expect(client.requests.first, baseline);
    expect(client.requests.last, 'She go home.\n');
    expect(
      find.text('First paragraph.\nShe goes home.\nThird paragraph.'),
      findsOneWidget,
    );
    expect(find.text('自动推荐：仅请求第 2 段'), findsWidgets);
  });

  testWidgets('manual recommendation also requests only changed paragraph', (
    tester,
  ) async {
    final client = _FakeCorrectionClient(
      resultBuilder: (text) => CorrectionResult(
        isAlreadyCorrect: false,
        suggestions: [
          CorrectionSuggestion(
            title: 'Incremental correction',
            english: text.replaceAll('They is ready.', 'They are ready.'),
            chineseExplanation: '只修正变化段落。',
            changes: const ['主谓一致'],
          ),
        ],
      ),
    );
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    const baseline = 'Intro.\nThey are ready.\nDone.';
    await tester.enterText(find.byKey(const Key('input_editor')), baseline);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    const edited = 'Intro.\nThey is ready.\nDone.';
    await tester.enterText(find.byKey(const Key('input_editor')), edited);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(client.requests, hasLength(2));
    expect(client.requests.last, 'They is ready.\n');
    expect(find.text('Intro.\nThey are ready.\nDone.'), findsOneWidget);
    expect(find.text('增量推荐：仅请求第 2 段'), findsWidgets);
  });

  testWidgets('paragraph deletion is applied locally without another request', (
    tester,
  ) async {
    final client = _FakeCorrectionClient(
      resultBuilder: (text) => CorrectionResult(
        isAlreadyCorrect: true,
        suggestions: [
          CorrectionSuggestion(
            title: 'Already correct',
            english: text,
            chineseExplanation: '文本已经正确。',
            changes: const [],
          ),
        ],
      ),
    );
    final controller = LangPilotController(
      correctionClient: client,
      settingsStore: _FakeSettingsStore(),
    );
    await controller.loadSettings();

    await tester.pumpWidget(LangPilotApp(controller: controller));

    const baseline = 'One.\nTwo.\nThree.';
    await tester.enterText(find.byKey(const Key('input_editor')), baseline);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    const edited = 'One.\nThree.';
    await tester.enterText(find.byKey(const Key('input_editor')), edited);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(client.requests, hasLength(1));
    expect(client.requests.single, baseline);
    final suggestionText = tester.widget<SelectableText>(
      find.byKey(const Key('suggestion_english_0')),
    );
    expect(suggestionText.data, edited);
    expect(find.text('增量推荐：本地应用删除'), findsWidgets);
    expect(find.text('增量部分'), findsOneWidget);
    expect(find.text('修改部分'), findsOneWidget);
    expect(find.text('Two.'), findsOneWidget);
  });
}

class _FakeCorrectionClient implements CorrectionClient {
  _FakeCorrectionClient({this.resultBuilder});

  final CorrectionResult Function(String text)? resultBuilder;

  int callCount = 0;
  final requests = <String>[];

  @override
  Future<CorrectionResult> correctText({
    required String text,
    required ModelSettings settings,
  }) async {
    callCount += 1;
    requests.add(text);
    final customResult = resultBuilder;
    if (customResult != null) {
      return customResult(text);
    }
    return const CorrectionResult(
      isAlreadyCorrect: false,
      suggestions: [
        CorrectionSuggestion(
          title: 'Natural correction',
          english: 'I have a clear plan.',
          chineseExplanation: '把中文意思自然翻译进英文，并修正 has 为 have。',
          changes: ['主谓一致', '中文译入英文'],
        ),
      ],
    );
  }
}

class _FakeSettingsStore implements SettingsStore {
  @override
  Future<ModelSettings> load() async {
    return const ModelSettings(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'test-key',
      model: 'fast-model',
    );
  }

  @override
  Future<void> save(ModelSettings settings) async {}
}
