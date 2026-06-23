import 'package:flutter_test/flutter_test.dart';
import 'package:langpilot/utils/incremental_paragraph.dart';

void main() {
  test(
    'finds the changed paragraph and composes it back into the document',
    () {
      final edit = IncrementalParagraphEdit.from(
        baseText: 'One.\nTwo is correct.\nThree.',
        currentText: 'One.\nTwo are wrong.\nThree.',
      );

      expect(edit.isPartialRequest, isTrue);
      expect(edit.scopeLabel, '第 2 段');
      expect(edit.changedText, 'Two are wrong.\n');
      expect(
        edit.compose('Two is correct.\n'),
        'One.\nTwo is correct.\nThree.',
      );
    },
  );

  test('falls back to full scope when the whole document is one paragraph', () {
    final edit = IncrementalParagraphEdit.from(
      baseText: 'I has a plan.',
      currentText: 'I have a plan.',
    );

    expect(edit.isPartialRequest, isFalse);
    expect(edit.scopeLabel, '全量文本');
  });

  test('detects paragraph deletion without changed request text', () {
    final edit = IncrementalParagraphEdit.from(
      baseText: 'One.\nTwo.\nThree.',
      currentText: 'One.\nThree.',
    );

    expect(edit.isDeletionOnlyChange, isTrue);
    expect(edit.hasChangedText, isFalse);
    expect(edit.changedText, isEmpty);
  });
}
