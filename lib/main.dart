import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'models/correction_result.dart';
import 'models/local_model_catalog.dart';
import 'models/model_settings.dart';
import 'services/correction_service.dart';
import 'services/local_model_manager.dart';
import 'services/local_model_manager_factory.dart';
import 'services/settings_store.dart';
import 'utils/incremental_paragraph.dart';
import 'utils/text_diff.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LangPilotApp());
}

class LangPilotApp extends StatelessWidget {
  const LangPilotApp({super.key, this.controller});

  final LangPilotController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LangPilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1c6b5b),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f9),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: const Color(0xff1f2933),
          displayColor: const Color(0xff1f2933),
        ),
      ),
      home: controller == null
          ? const _LangPilotBootstrap()
          : LangPilotHome(controller: controller!),
    );
  }
}

class _LangPilotBootstrap extends StatefulWidget {
  const _LangPilotBootstrap();

  @override
  State<_LangPilotBootstrap> createState() => _LangPilotBootstrapState();
}

class _LangPilotBootstrapState extends State<_LangPilotBootstrap> {
  late final CorrectionService _correctionService;
  late final LocalModelManager _localModelManager;
  late final LangPilotController _controller;

  @override
  void initState() {
    super.initState();
    _localModelManager = createLocalModelManager();
    _correctionService = CorrectionService(
      localModelManager: _localModelManager,
    );
    _controller = LangPilotController(
      correctionClient: _correctionService,
      settingsStore: LocalSettingsStore(),
      localModelManager: _localModelManager,
    );
    _controller.loadSettings();
  }

  @override
  void dispose() {
    _controller.dispose();
    _correctionService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LangPilotHome(controller: _controller);
  }
}

class LangPilotHome extends StatefulWidget {
  const LangPilotHome({super.key, required this.controller});

  final LangPilotController controller;

  @override
  State<LangPilotHome> createState() => _LangPilotHomeState();
}

class _LangPilotHomeState extends State<LangPilotHome> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  int? _activeSuggestionIndex;
  Timer? _actionClearTimer;
  Timer? _autoRecommendTimer;
  int _actionToken = 0;
  String _lastCheckedInput = '';
  String _diffSourceInput = '';
  String? _requestScopeStatus;
  String? _actionStatus;
  bool _isResultStale = false;
  bool _autoRecommendEnabled = false;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _actionClearTimer?.cancel();
    _autoRecommendTimer?.cancel();
    _inputController.removeListener(_handleInputChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    final hasResult = widget.controller.result != null;
    final nextIsStale =
        hasResult &&
        _lastCheckedInput.isNotEmpty &&
        _inputController.text.trim() != _lastCheckedInput.trim();

    if (nextIsStale != _isResultStale) {
      setState(() => _isResultStale = nextIsStale);
    }
    _scheduleAutoRecommend();
  }

  Future<void> _submit() {
    return _runCorrection(automatic: false);
  }

  Future<void> _runCorrection({required bool automatic}) async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      if (!automatic) {
        _inputFocusNode.requestFocus();
        _showActionFeedback('请输入内容。');
      }
      return;
    }

    if (!widget.controller.settings.isComplete) {
      if (automatic) {
        return;
      }
      await _openSettings();
      if (!mounted || !widget.controller.settings.isComplete) return;
    }

    if (widget.controller.settings.isLocalQwen) {
      final localStatus = await widget.controller.getLocalModelStatus(
        widget.controller.settings.localModelId,
      );
      if (!mounted) {
        return;
      }
      if (!localStatus.isReady) {
        if (!automatic) {
          _showActionFeedback(localStatus.message);
        }
        return;
      }
    }

    if (!automatic) {
      FocusScope.of(context).unfocus();
    }
    _autoRecommendTimer?.cancel();
    final incrementalEdit = IncrementalParagraphEdit.from(
      baseText: _lastCheckedInput,
      currentText: input,
    );

    if (incrementalEdit.isDeletionOnlyChange) {
      final status = automatic ? '自动推荐：本地应用删除' : '增量推荐：本地应用删除';
      widget.controller.applyLocalResult(
        CorrectionResult(
          isAlreadyCorrect: true,
          suggestions: [
            CorrectionSuggestion(
              title: '删除后的文本',
              english: input,
              chineseExplanation: '仅检测到段落删除，没有需要发送给模型的新内容。',
              changes: const ['本地增量：删除段落'],
            ),
          ],
        ),
        infoMessage: status,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _diffSourceInput = _lastCheckedInput;
        _lastCheckedInput = input;
        _isResultStale = _inputController.text.trim() != input;
        _activeSuggestionIndex = null;
        _requestScopeStatus = status;
        _actionStatus = status;
      });
      return;
    }

    final shouldUseIncremental = incrementalEdit.isPartialRequest;
    final requestPrefix = automatic ? '自动推荐' : '增量推荐';
    final requestText = shouldUseIncremental
        ? incrementalEdit.changedText
        : input;

    await widget.controller.correctText(
      requestText,
      transformResult: shouldUseIncremental
          ? (result) => _composeIncrementalResult(result, incrementalEdit)
          : null,
      infoMessage: shouldUseIncremental
          ? '$requestPrefix：仅请求${incrementalEdit.scopeLabel}'
          : null,
    );
    if (!mounted) {
      return;
    }
    if (widget.controller.result != null &&
        widget.controller.errorMessage == null) {
      setState(() {
        _diffSourceInput = input;
        _lastCheckedInput = input;
        _isResultStale = _inputController.text.trim() != input;
        _activeSuggestionIndex = null;
        _requestScopeStatus = shouldUseIncremental
            ? '$requestPrefix：仅请求${incrementalEdit.scopeLabel}'
            : null;
        _actionStatus = _requestScopeStatus;
      });
    }
  }

  CorrectionResult _composeIncrementalResult(
    CorrectionResult partialResult,
    IncrementalParagraphEdit edit,
  ) {
    final suggestions = partialResult.suggestions
        .map(
          (suggestion) => CorrectionSuggestion(
            title: suggestion.title,
            english: edit.compose(suggestion.english),
            chineseExplanation: suggestion.chineseExplanation,
            changes: ['增量请求：${edit.scopeLabel}', ...suggestion.changes],
          ),
        )
        .toList(growable: false);

    return CorrectionResult(
      isAlreadyCorrect: partialResult.isAlreadyCorrect,
      suggestions: suggestions,
    );
  }

  Future<void> _copySuggestion(CorrectionSuggestion suggestion) async {
    await Clipboard.setData(ClipboardData(text: suggestion.english));
    if (!mounted) {
      return;
    }
    final index = widget.controller.result?.suggestions.indexOf(suggestion);
    _showActionFeedback('已复制推荐结果。', index: index);
  }

  void _replaceWithSuggestion(int index) {
    final suggestions = widget.controller.result?.suggestions;
    if (suggestions == null || index < 0 || index >= suggestions.length) {
      return;
    }

    final text = suggestions[index].english;
    _diffSourceInput = text;
    _lastCheckedInput = text;
    _isResultStale = false;
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocusNode.requestFocus();
    _showActionFeedback('已替换到输入框。', index: index);
  }

  Future<void> _setAutoRecommendEnabled(bool value) async {
    if (value && !widget.controller.settings.isComplete) {
      await _openSettings();
      if (!mounted || !widget.controller.settings.isComplete) {
        _showActionFeedback('请先配置模型后再开启自动推荐。');
        return;
      }
    }

    setState(() => _autoRecommendEnabled = value);
    if (value) {
      _scheduleAutoRecommend();
    } else {
      _autoRecommendTimer?.cancel();
    }
  }

  void _scheduleAutoRecommend() {
    _autoRecommendTimer?.cancel();
    if (!_autoRecommendEnabled || !widget.controller.settings.isComplete) {
      return;
    }

    final input = _inputController.text.trim();
    if (input.isEmpty) {
      return;
    }

    _autoRecommendTimer = Timer(
      widget.controller.settings.autoRecommendDelay,
      _triggerAutoRecommend,
    );
  }

  void _triggerAutoRecommend() {
    if (!mounted || !_autoRecommendEnabled) {
      return;
    }

    final input = _inputController.text.trim();
    if (input.isEmpty || !widget.controller.settings.isComplete) {
      return;
    }

    final alreadyChecked =
        input == _lastCheckedInput.trim() &&
        widget.controller.result != null &&
        widget.controller.errorMessage == null;
    if (alreadyChecked) {
      return;
    }

    if (widget.controller.isChecking) {
      _autoRecommendTimer?.cancel();
      _autoRecommendTimer = Timer(
        const Duration(milliseconds: 500),
        _triggerAutoRecommend,
      );
      return;
    }

    _runCorrection(automatic: true);
  }

  void _showActionFeedback(String message, {int? index}) {
    final token = ++_actionToken;
    setState(() {
      _actionStatus = message;
      _activeSuggestionIndex = index;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
        ),
      );

    _actionClearTimer?.cancel();
    _actionClearTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted || token != _actionToken) {
        return;
      }
      setState(() {
        _actionStatus = null;
        _activeSuggestionIndex = null;
      });
    });
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(controller: widget.controller),
    );
    if (mounted && _autoRecommendEnabled) {
      _scheduleAutoRecommend();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter, control: true):
                _SubmitCorrectionIntent(),
            SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _SubmitCorrectionIntent(),
            SingleActivator(LogicalKeyboardKey.digit1, alt: true):
                _ApplySuggestionIntent(0),
            SingleActivator(LogicalKeyboardKey.digit2, alt: true):
                _ApplySuggestionIntent(1),
            SingleActivator(LogicalKeyboardKey.digit3, alt: true):
                _ApplySuggestionIntent(2),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _SubmitCorrectionIntent: CallbackAction<_SubmitCorrectionIntent>(
                onInvoke: (_) {
                  _submit();
                  return null;
                },
              ),
              _ApplySuggestionIntent: CallbackAction<_ApplySuggestionIntent>(
                onInvoke: (intent) {
                  _replaceWithSuggestion(intent.index);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                appBar: AppBar(
                  titleSpacing: 20,
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.spellcheck),
                      SizedBox(width: 10),
                      Text('LangPilot'),
                    ],
                  ),
                  actions: [
                    _ModelStatusPill(settings: widget.controller.settings),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('settings_button'),
                      tooltip: '模型设置',
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                body: widget.controller.isLoadingSettings
                    ? const Center(child: CircularProgressIndicator())
                    : _Workspace(
                        controller: widget.controller,
                        inputController: _inputController,
                        inputFocusNode: _inputFocusNode,
                        checkedInput: _lastCheckedInput,
                        diffSourceInput: _diffSourceInput,
                        activeSuggestionIndex: _activeSuggestionIndex,
                        actionStatus: _actionStatus ?? _requestScopeStatus,
                        isResultStale: _isResultStale,
                        autoRecommendEnabled: _autoRecommendEnabled,
                        autoRecommendDelay:
                            widget.controller.settings.autoRecommendDelay,
                        onSubmit: _submit,
                        onAutoRecommendChanged: _setAutoRecommendEnabled,
                        onCopy: _copySuggestion,
                        onReplace: _replaceWithSuggestion,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.controller,
    required this.inputController,
    required this.inputFocusNode,
    required this.checkedInput,
    required this.diffSourceInput,
    required this.activeSuggestionIndex,
    required this.actionStatus,
    required this.isResultStale,
    required this.autoRecommendEnabled,
    required this.autoRecommendDelay,
    required this.onSubmit,
    required this.onAutoRecommendChanged,
    required this.onCopy,
    required this.onReplace,
  });

  final LangPilotController controller;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final String checkedInput;
  final String diffSourceInput;
  final int? activeSuggestionIndex;
  final String? actionStatus;
  final bool isResultStale;
  final bool autoRecommendEnabled;
  final Duration autoRecommendDelay;
  final VoidCallback onSubmit;
  final ValueChanged<bool> onAutoRecommendChanged;
  final ValueChanged<CorrectionSuggestion> onCopy;
  final ValueChanged<int> onReplace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        final padding = EdgeInsets.symmetric(
          horizontal: isWide ? 28 : 16,
          vertical: isWide ? 24 : 16,
        );

        if (isWide) {
          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: _InputPane(
                    controller: controller,
                    inputController: inputController,
                    inputFocusNode: inputFocusNode,
                    isWide: true,
                    autoRecommendEnabled: autoRecommendEnabled,
                    autoRecommendDelay: autoRecommendDelay,
                    onSubmit: onSubmit,
                    onAutoRecommendChanged: onAutoRecommendChanged,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: _ResultPane(
                    controller: controller,
                    isWide: true,
                    checkedInput: checkedInput,
                    diffSourceInput: diffSourceInput,
                    activeSuggestionIndex: activeSuggestionIndex,
                    actionStatus: actionStatus,
                    isResultStale: isResultStale,
                    onCopy: onCopy,
                    onReplace: onReplace,
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            children: [
              _InputPane(
                controller: controller,
                inputController: inputController,
                inputFocusNode: inputFocusNode,
                isWide: false,
                autoRecommendEnabled: autoRecommendEnabled,
                autoRecommendDelay: autoRecommendDelay,
                onSubmit: onSubmit,
                onAutoRecommendChanged: onAutoRecommendChanged,
              ),
              const SizedBox(height: 20),
              _ResultPane(
                controller: controller,
                isWide: false,
                checkedInput: checkedInput,
                diffSourceInput: diffSourceInput,
                activeSuggestionIndex: activeSuggestionIndex,
                actionStatus: actionStatus,
                isResultStale: isResultStale,
                onCopy: onCopy,
                onReplace: onReplace,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InputPane extends StatelessWidget {
  const _InputPane({
    required this.controller,
    required this.inputController,
    required this.inputFocusNode,
    required this.isWide,
    required this.autoRecommendEnabled,
    required this.autoRecommendDelay,
    required this.onSubmit,
    required this.onAutoRecommendChanged,
  });

  final LangPilotController controller;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final bool isWide;
  final bool autoRecommendEnabled;
  final Duration autoRecommendDelay;
  final VoidCallback onSubmit;
  final ValueChanged<bool> onAutoRecommendChanged;

  @override
  Widget build(BuildContext context) {
    final editor = _EditorFrame(
      focusNode: inputFocusNode,
      child: TextField(
        key: const Key('input_editor'),
        controller: inputController,
        focusNode: inputFocusNode,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 16, height: 1.55),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(18),
          hintText: 'Write or paste English here. 中文片段也可以直接输入。',
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaneHeader(
          icon: Icons.edit_note,
          title: '写作输入',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: inputController,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Text(
                          '${value.text.characters.length} 字符',
                          key: ValueKey(value.text.characters.length),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _AutoRecommendSwitch(
                        value: autoRecommendEnabled,
                        delay: autoRecommendDelay,
                        onChanged: onAutoRecommendChanged,
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: '清空',
                        onPressed: hasText ? inputController.clear : null,
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const Key('submit_button'),
                        onPressed: hasText && !controller.isChecking
                            ? onSubmit
                            : null,
                        icon: controller.isChecking
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: const Text('纠错'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (isWide)
          Expanded(child: editor)
        else
          SizedBox(height: 320, child: editor),
      ],
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({
    required this.controller,
    required this.isWide,
    required this.checkedInput,
    required this.diffSourceInput,
    required this.activeSuggestionIndex,
    required this.actionStatus,
    required this.isResultStale,
    required this.onCopy,
    required this.onReplace,
  });

  final LangPilotController controller;
  final bool isWide;
  final String checkedInput;
  final String diffSourceInput;
  final int? activeSuggestionIndex;
  final String? actionStatus;
  final bool isResultStale;
  final ValueChanged<CorrectionSuggestion> onCopy;
  final ValueChanged<int> onReplace;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    final suggestions = result?.suggestions ?? const <CorrectionSuggestion>[];

    final body = <Widget>[
      if (controller.isChecking)
        const _CheckingPanel()
      else if (controller.errorMessage != null)
        _InlineMessage(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          message: controller.errorMessage!,
        )
      else if (result == null)
        const _EmptyResults()
      else ...[
        if (result.isAlreadyCorrect)
          _InlineMessage(
            icon: Icons.check_circle_outline,
            color: const Color(0xff24845f),
            message: '语法正确。',
          ),
        if (isResultStale)
          const _InlineMessage(
            icon: Icons.history_toggle_off,
            color: Color(0xff8b5b00),
            message: '输入已修改，当前推荐来自上一版内容。',
          ),
        if (actionStatus != null)
          _InlineMessage(
            icon: Icons.done_all,
            color: const Color(0xff1d6f50),
            message: actionStatus!,
          ),
      ],
    ];

    final list = ListView.separated(
      shrinkWrap: !isWide,
      physics: isWide
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _StaggeredFadeSlide(
          key: ValueKey('${suggestions[index].english}-$index'),
          index: index,
          child: _SuggestionCard(
            index: index,
            suggestion: suggestions[index],
            sourceText: diffSourceInput.isEmpty
                ? checkedInput
                : diffSourceInput,
            isActive: activeSuggestionIndex == index,
            onCopy: () => onCopy(suggestions[index]),
            onReplace: () => onReplace(index),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PaneHeader(icon: Icons.preview_outlined, title: '推荐结果'),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Column(
              key: ValueKey(
                '${controller.isChecking}-${controller.errorMessage}-${result == null}-${result?.isAlreadyCorrect}-$isResultStale-$actionStatus',
              ),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < body.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  body[i],
                ],
              ],
            ),
          ),
        ),
        if (body.isNotEmpty && suggestions.isNotEmpty)
          const SizedBox(height: 12),
        if (suggestions.isNotEmpty) isWide ? Expanded(child: list) : list,
      ],
    );
  }
}

class _AutoRecommendSwitch extends StatelessWidget {
  const _AutoRecommendSwitch({
    required this.value,
    required this.delay,
    required this.onChanged,
  });

  final bool value;
  final Duration delay;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '停止编辑 ${_formatSeconds(delay)} 秒后自动推荐',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: value ? const Color(0xffe6f2ec) : const Color(0xffeef1f4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.flash_on : Icons.flash_off,
                size: 16,
                color: value
                    ? const Color(0xff1d6f50)
                    : const Color(0xff66727f),
              ),
              const SizedBox(width: 4),
              Text(
                '自动',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: value
                      ? const Color(0xff1d6f50)
                      : const Color(0xff4b5b68),
                ),
              ),
              Switch.adaptive(
                key: const Key('auto_recommend_switch'),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSeconds(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  if (seconds == seconds.roundToDouble()) {
    return seconds.toStringAsFixed(0);
  }
  return seconds.toStringAsFixed(1);
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.index,
    required this.suggestion,
    required this.sourceText,
    required this.isActive,
    required this.onCopy,
    required this.onReplace,
  });

  final int index;
  final CorrectionSuggestion suggestion;
  final String sourceText;
  final bool isActive;
  final VoidCallback onCopy;
  final VoidCallback onReplace;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isActive || _isHovered;
    final borderColor = widget.isActive
        ? Theme.of(context).colorScheme.primary
        : _isHovered
        ? const Color(0xff9fb4aa)
        : const Color(0xffdce3ea);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _isHovered ? 1.01 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.isActive ? const Color(0xfff1f8f4) : Colors.white,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: const Color(0xff1c6b5b).withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onCopy,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.index + 1}. ${widget.suggestion.title}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制',
                          onPressed: widget.onCopy,
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          key: Key('replace_suggestion_${widget.index}'),
                          tooltip: '替换输入',
                          onPressed: widget.onReplace,
                          icon: const Icon(Icons.keyboard_return),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      widget.suggestion.english,
                      key: Key('suggestion_english_${widget.index}'),
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                    if (widget.suggestion.chineseExplanation.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.suggestion.chineseExplanation,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xff4b5b68),
                          height: 1.45,
                        ),
                      ),
                    ],
                    _SuggestionDiff(
                      sourceText: widget.sourceText,
                      targetText: widget.suggestion.english,
                    ),
                    if (widget.suggestion.changes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final change in widget.suggestion.changes)
                            Chip(
                              label: Text(change),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide.none,
                              backgroundColor: const Color(0xffeef4f1),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionDiff extends StatelessWidget {
  const _SuggestionDiff({required this.sourceText, required this.targetText});

  final String sourceText;
  final String targetText;

  @override
  Widget build(BuildContext context) {
    if (sourceText.trim().isEmpty || targetText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final diff = TextDiffer.compare(sourceText, targetText);
    final hasChanges =
        diff.additions.isNotEmpty || diff.modifications.isNotEmpty;
    if (!hasChanges) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xfff8fafb),
          border: Border.all(color: const Color(0xffdce3ea)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.difference_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '修改对比',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (diff.isTruncated) ...[
                    const SizedBox(width: 8),
                    Text(
                      '长文本摘要',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xff8b5b00),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SelectableText.rich(
                TextSpan(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                  children: [
                    for (final segment in diff.segments)
                      TextSpan(
                        text: segment.text,
                        style: _diffTextStyle(context, segment.type),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _DiffChangeSection(
                title: '增量部分',
                emptyText: '无新增内容',
                changes: diff.additions,
                color: const Color(0xff1d6f50),
              ),
              const SizedBox(height: 8),
              _DiffChangeSection(
                title: '修改部分',
                emptyText: '无替换或删除',
                changes: diff.modifications,
                color: const Color(0xff9b2f2f),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle? _diffTextStyle(BuildContext context, DiffSegmentType type) {
    final base = Theme.of(context).textTheme.bodyMedium;
    switch (type) {
      case DiffSegmentType.equal:
        return base?.copyWith(color: const Color(0xff33414f));
      case DiffSegmentType.inserted:
        return base?.copyWith(
          color: const Color(0xff0f6b49),
          backgroundColor: const Color(0xffdff3e8),
          fontWeight: FontWeight.w700,
        );
      case DiffSegmentType.deleted:
        return base?.copyWith(
          color: const Color(0xff9b2f2f),
          backgroundColor: const Color(0xffffe5e5),
          decoration: TextDecoration.lineThrough,
        );
    }
  }
}

class _DiffChangeSection extends StatelessWidget {
  const _DiffChangeSection({
    required this.title,
    required this.emptyText,
    required this.changes,
    required this.color,
  });

  final String title;
  final String emptyText;
  final List<DiffChange> changes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visibleChanges = changes.take(8).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xff33414f),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (visibleChanges.isEmpty)
          Text(
            emptyText,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xff6b7682)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final change in visibleChanges)
                _DiffChip(change: change, color: color),
              if (changes.length > visibleChanges.length)
                Chip(
                  label: Text('+${changes.length - visibleChanges.length}'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: const Color(0xffeef1f4),
                ),
            ],
          ),
      ],
    );
  }
}

class _DiffChip extends StatelessWidget {
  const _DiffChip({required this.change, required this.color});

  final DiffChange change;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rawLabel = change.isAddition
        ? change.revised
        : change.revised.trim().isEmpty
        ? change.original
        : '${change.original} -> ${change.revised}';
    final label = rawLabel.characters.length > 90
        ? '${rawLabel.characters.take(90).toString()}...'
        : rawLabel;

    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.18)),
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: const Color(0xff26323d)),
    );
  }
}

class _EditorFrame extends StatelessWidget {
  const _EditorFrame({required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: focused
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xffd5dce3),
              width: focused ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
    );
  }
}

class _CheckingPanel extends StatelessWidget {
  const _CheckingPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '正在生成推荐...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xff33414f),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }
}

class _StaggeredFadeSlide extends StatelessWidget {
  const _StaggeredFadeSlide({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});

  final LangPilotController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _localTokenController;
  late final TextEditingController _autoDelayController;
  late final Listenable _fieldListenable;
  late ModelProvider _provider;
  late String _localModelId;
  bool _obscureKey = true;
  bool _obscureLocalToken = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _isLoadingLocalStatus = false;
  bool _isDownloadingLocalModel = false;
  double? _downloadProgress;
  LocalModelStatus? _localModelStatus;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _provider = settings.provider;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _modelController = TextEditingController(text: settings.model);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _localTokenController = TextEditingController(
      text: settings.localModelAccessToken,
    );
    _localModelId = settings.localModelId;
    _autoDelayController = TextEditingController(
      text: _formatSeconds(settings.autoRecommendDelay),
    );
    _fieldListenable = Listenable.merge([
      _baseUrlController,
      _modelController,
      _apiKeyController,
      _localTokenController,
      _autoDelayController,
    ]);
    _loadLocalStatus();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _localTokenController.dispose();
    _autoDelayController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalStatus() async {
    if (_provider != ModelProvider.localQwen) {
      return;
    }
    setState(() => _isLoadingLocalStatus = true);
    try {
      _localModelStatus = await widget.controller.getLocalModelStatus(
        _localModelId,
      );
    } catch (error) {
      _testMessage = error.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocalStatus = false);
      }
    }
  }

  Future<void> _selectProvider(ModelProvider provider) async {
    if (_provider == provider) {
      return;
    }
    setState(() {
      _provider = provider;
      _testMessage = null;
    });
    if (provider == ModelProvider.localQwen) {
      await _loadLocalStatus();
    }
  }

  Future<void> _selectLocalModel(String? value) async {
    if (value == null || value == _localModelId) {
      return;
    }
    setState(() {
      _localModelId = value;
      _testMessage = null;
    });
    await _loadLocalStatus();
  }

  double? _parsedAutoDelaySeconds() {
    return double.tryParse(_autoDelayController.text.trim());
  }

  int? _parsedAutoDelayMs() {
    final seconds = _parsedAutoDelaySeconds();
    if (seconds == null) {
      return null;
    }
    final milliseconds = (seconds * 1000).round();
    if (milliseconds < ModelSettings.minAutoRecommendDelayMs ||
        milliseconds > ModelSettings.maxAutoRecommendDelayMs) {
      return null;
    }
    return milliseconds;
  }

  bool _canUseCurrentSettings() {
    final delayMs = _parsedAutoDelayMs();
    if (delayMs == null) {
      return false;
    }
    switch (_provider) {
      case ModelProvider.online:
        return _baseUrlController.text.trim().isNotEmpty &&
            _modelController.text.trim().isNotEmpty &&
            _apiKeyController.text.trim().isNotEmpty;
      case ModelProvider.localQwen:
        return _localModelId.trim().isNotEmpty;
    }
  }

  ModelSettings _settingsFromFields() {
    return ModelSettings(
      provider: _provider,
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      localModelId: _localModelId.trim(),
      localModelAccessToken: _localTokenController.text.trim(),
      autoRecommendDelayMs:
          _parsedAutoDelayMs() ?? ModelSettings.defaultAutoRecommendDelayMs,
    );
  }

  Future<void> _testConnection() async {
    if (!_settingsFromFields().isComplete) {
      setState(() => _testMessage = '请先填写完整模型设置。');
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    try {
      await widget.controller.testSettings(_settingsFromFields());
      _testMessage = '连接可用。';
    } catch (error) {
      _testMessage = error.toString();
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _downloadLocalModel() async {
    setState(() {
      _isDownloadingLocalModel = true;
      _downloadProgress = 0;
      _testMessage = null;
    });

    try {
      await widget.controller.downloadLocalModel(
        _localModelId,
        accessToken: _localTokenController.text.trim(),
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _downloadProgress = progress.fraction;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _testMessage = '已下载 ${localModelById(_localModelId).displayName}。';
        _downloadProgress = 1;
      });
      await _loadLocalStatus();
    } catch (error) {
      if (mounted) {
        setState(() => _testMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingLocalModel = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_settingsFromFields().isComplete) {
      setState(() => _testMessage = '请先填写完整模型设置。');
      return;
    }

    if (_parsedAutoDelayMs() == null) {
      setState(() => _testMessage = '自动推荐等待时间需要在 0.5 到 30 秒之间。');
      return;
    }

    setState(() {
      _isSaving = true;
      _testMessage = null;
    });

    try {
      await widget.controller.saveSettings(_settingsFromFields());
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _testMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedLocalModel = localModelById(_localModelId);
    return AlertDialog(
      title: const Row(
        children: [Icon(Icons.tune), SizedBox(width: 10), Text('模型设置')],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<ModelProvider>(
                segments: const [
                  ButtonSegment<ModelProvider>(
                    value: ModelProvider.online,
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('在线模型'),
                  ),
                  ButtonSegment<ModelProvider>(
                    value: ModelProvider.localQwen,
                    icon: Icon(Icons.download_for_offline_outlined),
                    label: Text('本地 Qwen'),
                  ),
                ],
                selected: {_provider},
                onSelectionChanged: (selection) {
                  _selectProvider(selection.first);
                },
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _provider == ModelProvider.online
                    ? Column(
                        key: const ValueKey('online_settings'),
                        children: [
                          TextField(
                            controller: _baseUrlController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Endpoint（默认）',
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _modelController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Model（默认）',
                              prefixIcon: Icon(Icons.memory),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              prefixIcon: const Icon(Icons.key),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? '显示' : '隐藏',
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InlineMessage(
                            icon: Icons.info_outline,
                            color: const Color(0xff5b6570),
                            message: kIsWeb
                                ? 'Web 端会把 Key 保存在当前浏览器本地环境。'
                                : 'API Key 会保存在本机本地设置中。',
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('local_settings'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<LocalModelDefinition>(
                            initialValue: selectedLocalModel,
                            decoration: const InputDecoration(
                              labelText: '本地模型',
                              prefixIcon: Icon(Icons.developer_board),
                            ),
                            items: [
                              for (final model in localQwenModels)
                                DropdownMenuItem<LocalModelDefinition>(
                                  value: model,
                                  child: Text(
                                    '${model.displayName}  ${model.sizeLabel}',
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              _selectLocalModel(value?.id);
                            },
                          ),
                          const SizedBox(height: 12),
                          _InlineMessage(
                            icon: Icons.info_outline,
                            color: const Color(0xff5b6570),
                            message: selectedLocalModel.description,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _localTokenController,
                            obscureText: _obscureLocalToken,
                            decoration: InputDecoration(
                              labelText: 'Hugging Face Token',
                              hintText: selectedLocalModel.requiresDownloadToken
                                  ? '下载该模型需要 token'
                                  : '可选，私有或限权模型需要',
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                tooltip: _obscureLocalToken ? '显示' : '隐藏',
                                onPressed: () => setState(
                                  () =>
                                      _obscureLocalToken = !_obscureLocalToken,
                                ),
                                icon: Icon(
                                  _obscureLocalToken
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InlineMessage(
                            icon: _localModelStatus?.isDownloaded == true
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_outlined,
                            color: _localModelStatus?.isDownloaded == true
                                ? const Color(0xff24845f)
                                : const Color(0xff8b5b00),
                            message:
                                _localModelStatus?.message ?? '正在读取本地模型状态...',
                          ),
                          if (_isLoadingLocalStatus) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 3),
                          ],
                          if (_downloadProgress != null &&
                              _isDownloadingLocalModel) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _downloadProgress,
                              minHeight: 3,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed:
                                    (_localModelStatus?.canDownload ?? false) &&
                                        !_isDownloadingLocalModel
                                    ? _downloadLocalModel
                                    : null,
                                icon: _isDownloadingLocalModel
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download),
                                label: Text(
                                  _localModelStatus?.canDownload == false
                                      ? '不支持下载'
                                      : _localModelStatus?.isDownloaded == true
                                      ? '重新下载'
                                      : '下载',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _localModelStatus?.canRunInference == true
                                      ? '下载后 Desktop 可离线纠错；Web 和 App 会提示不支持。'
                                      : '当前环境或模型没有可用的本地推理文件。',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _autoDelayController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '自动推荐等待时间',
                  hintText: '2.0',
                  suffixText: '秒',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _InlineMessage(
                icon: Icons.info_outline,
                color: const Color(0xff5b6570),
                message: '停止编辑后按这个时间自动触发推荐。',
              ),
              const SizedBox(height: 12),
              if (_testMessage != null) ...[
                const SizedBox(height: 12),
                _InlineMessage(
                  icon: _testMessage == '连接可用。'
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: _testMessage == '连接可用。'
                      ? const Color(0xff24845f)
                      : Theme.of(context).colorScheme.error,
                  message: _testMessage!,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ListenableBuilder(
          listenable: _fieldListenable,
          builder: (context, _) {
            final canUse = _canUseCurrentSettings();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: canUse && !_isTesting && !_isSaving
                      ? _testConnection
                      : null,
                  icon: _isTesting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('测试'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canUse && !_isTesting && !_isSaving ? _save : null,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );

    if (trailing == null) {
      return titleRow;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: trailing!,
              ),
            ],
          );
        }

        return Row(children: [titleRow, const Spacer(), trailing!]);
      },
    );
  }
}

class _ModelStatusPill extends StatelessWidget {
  const _ModelStatusPill({required this.settings});

  final ModelSettings settings;

  @override
  Widget build(BuildContext context) {
    final ready = settings.isComplete;
    final isLocal = settings.isLocalQwen;
    final color = !ready
        ? const Color(0xfffff1d6)
        : isLocal
        ? const Color(0xfffff1d6)
        : const Color(0xffe6f2ec);
    final iconColor = !ready || isLocal
        ? const Color(0xff8b5b00)
        : const Color(0xff1d6f50);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            !ready
                ? Icons.warning_amber_outlined
                : isLocal
                ? Icons.download_for_offline_outlined
                : Icons.check_circle_outline,
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              ready ? settings.displayName : '未配置',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xff33414f),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffdce3ea)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '等待预览',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitCorrectionIntent extends Intent {
  const _SubmitCorrectionIntent();
}

class _ApplySuggestionIntent extends Intent {
  const _ApplySuggestionIntent(this.index);

  final int index;
}
