class IncrementalParagraphEdit {
  const IncrementalParagraphEdit({
    required this.baseText,
    required this.currentText,
    required this.changedText,
    required this.startOffset,
    required this.endOffset,
    required this.firstParagraph,
    required this.lastParagraph,
    required this.totalParagraphs,
  });

  final String baseText;
  final String currentText;
  final String changedText;
  final int startOffset;
  final int endOffset;
  final int firstParagraph;
  final int lastParagraph;
  final int totalParagraphs;

  bool get hasChangedText => changedText.trim().isNotEmpty;

  bool get hasAnyChange => baseText.trim() != currentText.trim();

  bool get isDeletionOnlyChange =>
      hasAnyChange && !hasChangedText && baseText.trim().isNotEmpty;

  bool get isPartialRequest =>
      hasChangedText &&
      baseText.trim().isNotEmpty &&
      changedText.trim().length < currentText.trim().length;

  String get scopeLabel {
    if (!isPartialRequest) {
      return '全量文本';
    }
    if (firstParagraph == lastParagraph) {
      return '第 $firstParagraph 段';
    }
    return '第 $firstParagraph-$lastParagraph 段';
  }

  String compose(String revisedChangedText) {
    return currentText.replaceRange(startOffset, endOffset, revisedChangedText);
  }

  static IncrementalParagraphEdit from({
    required String baseText,
    required String currentText,
  }) {
    final base = _splitParagraphs(baseText);
    final current = _splitParagraphs(currentText);

    var prefix = 0;
    while (prefix < base.length &&
        prefix < current.length &&
        base[prefix].text == current[prefix].text) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < base.length - prefix &&
        suffix < current.length - prefix &&
        base[base.length - 1 - suffix].text ==
            current[current.length - 1 - suffix].text) {
      suffix += 1;
    }

    final currentStartIndex = prefix;
    final currentEndIndex = current.length - suffix;
    final startOffset = currentStartIndex < current.length
        ? current[currentStartIndex].startOffset
        : currentText.length;
    final endOffset = currentEndIndex > currentStartIndex
        ? current[currentEndIndex - 1].endOffset
        : startOffset;
    final changedText = currentText.substring(startOffset, endOffset);

    final firstParagraph = current.isEmpty
        ? 1
        : currentStartIndex.clamp(0, current.length - 1) + 1;
    final lastParagraph = currentEndIndex > currentStartIndex
        ? currentEndIndex
        : firstParagraph;

    return IncrementalParagraphEdit(
      baseText: baseText,
      currentText: currentText,
      changedText: changedText,
      startOffset: startOffset,
      endOffset: endOffset,
      firstParagraph: firstParagraph,
      lastParagraph: lastParagraph,
      totalParagraphs: current.isEmpty ? 1 : current.length,
    );
  }

  static List<_ParagraphSlice> _splitParagraphs(String text) {
    if (text.isEmpty) {
      return const [];
    }

    final paragraphs = <_ParagraphSlice>[];
    var start = 0;
    while (start < text.length) {
      final newline = text.indexOf('\n', start);
      final end = newline == -1 ? text.length : newline + 1;
      paragraphs.add(
        _ParagraphSlice(
          text: text.substring(start, end),
          startOffset: start,
          endOffset: end,
        ),
      );
      start = end;
    }
    return paragraphs;
  }
}

class _ParagraphSlice {
  const _ParagraphSlice({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final int startOffset;
  final int endOffset;
}
