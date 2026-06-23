enum DiffSegmentType { equal, inserted, deleted }

class DiffSegment {
  const DiffSegment({required this.type, required this.text});

  final DiffSegmentType type;
  final String text;
}

class DiffChange {
  const DiffChange({required this.original, required this.revised});

  final String original;
  final String revised;

  bool get isAddition => original.trim().isEmpty && revised.trim().isNotEmpty;
  bool get isModification => original.trim().isNotEmpty;
}

class TextDiffResult {
  const TextDiffResult({
    required this.segments,
    required this.additions,
    required this.modifications,
    required this.isTruncated,
  });

  final List<DiffSegment> segments;
  final List<DiffChange> additions;
  final List<DiffChange> modifications;
  final bool isTruncated;
}

class TextDiffer {
  const TextDiffer._();

  static final _tokenPattern = RegExp(
    r"\s+|[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*|[\u4E00-\u9FFF]+|[^\sA-Za-z0-9\u4E00-\u9FFF]+",
    unicode: true,
  );

  static TextDiffResult compare(String source, String target) {
    final sourceTokens = _tokenize(source);
    final targetTokens = _tokenize(target);

    if (sourceTokens.isEmpty && targetTokens.isEmpty) {
      return const TextDiffResult(
        segments: [],
        additions: [],
        modifications: [],
        isTruncated: false,
      );
    }

    final isTruncated = sourceTokens.length * targetTokens.length > 180000;
    if (isTruncated) {
      return TextDiffResult(
        segments: [DiffSegment(type: DiffSegmentType.inserted, text: target)],
        additions: [DiffChange(original: '', revised: target)],
        modifications: source.trim().isEmpty
            ? const []
            : [DiffChange(original: source, revised: target)],
        isTruncated: true,
      );
    }

    final segments = _compact(_buildSegments(sourceTokens, targetTokens));
    final changes = _collectChanges(segments);
    return TextDiffResult(
      segments: segments,
      additions: changes.where((change) => change.isAddition).toList(),
      modifications: changes.where((change) => change.isModification).toList(),
      isTruncated: false,
    );
  }

  static List<String> _tokenize(String text) {
    return _tokenPattern
        .allMatches(text)
        .map((match) => match.group(0) ?? '')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static List<DiffSegment> _buildSegments(
    List<String> sourceTokens,
    List<String> targetTokens,
  ) {
    final rows = sourceTokens.length;
    final columns = targetTokens.length;
    final lcs = List.generate(
      rows + 1,
      (_) => List<int>.filled(columns + 1, 0),
      growable: false,
    );

    for (var row = rows - 1; row >= 0; row--) {
      for (var column = columns - 1; column >= 0; column--) {
        if (sourceTokens[row] == targetTokens[column]) {
          lcs[row][column] = lcs[row + 1][column + 1] + 1;
        } else {
          lcs[row][column] = lcs[row + 1][column] >= lcs[row][column + 1]
              ? lcs[row + 1][column]
              : lcs[row][column + 1];
        }
      }
    }

    final segments = <DiffSegment>[];
    var row = 0;
    var column = 0;
    while (row < rows && column < columns) {
      if (sourceTokens[row] == targetTokens[column]) {
        segments.add(
          DiffSegment(type: DiffSegmentType.equal, text: sourceTokens[row]),
        );
        row += 1;
        column += 1;
      } else if (lcs[row + 1][column] >= lcs[row][column + 1]) {
        segments.add(
          DiffSegment(type: DiffSegmentType.deleted, text: sourceTokens[row]),
        );
        row += 1;
      } else {
        segments.add(
          DiffSegment(
            type: DiffSegmentType.inserted,
            text: targetTokens[column],
          ),
        );
        column += 1;
      }
    }

    while (row < rows) {
      segments.add(
        DiffSegment(type: DiffSegmentType.deleted, text: sourceTokens[row]),
      );
      row += 1;
    }
    while (column < columns) {
      segments.add(
        DiffSegment(type: DiffSegmentType.inserted, text: targetTokens[column]),
      );
      column += 1;
    }

    return segments;
  }

  static List<DiffSegment> _compact(List<DiffSegment> segments) {
    final compacted = <DiffSegment>[];
    for (final segment in segments) {
      if (compacted.isNotEmpty && compacted.last.type == segment.type) {
        final previous = compacted.removeLast();
        compacted.add(
          DiffSegment(type: previous.type, text: previous.text + segment.text),
        );
      } else {
        compacted.add(segment);
      }
    }
    return compacted;
  }

  static List<DiffChange> _collectChanges(List<DiffSegment> segments) {
    final changes = <DiffChange>[];
    final original = StringBuffer();
    final revised = StringBuffer();

    void flush() {
      final originalText = original.toString().trim();
      final revisedText = revised.toString().trim();
      if (originalText.isNotEmpty || revisedText.isNotEmpty) {
        changes.add(DiffChange(original: originalText, revised: revisedText));
      }
      original.clear();
      revised.clear();
    }

    for (final segment in segments) {
      if (segment.type == DiffSegmentType.equal) {
        flush();
      } else if (segment.type == DiffSegmentType.deleted) {
        original.write(segment.text);
      } else {
        revised.write(segment.text);
      }
    }
    flush();

    return changes;
  }
}
