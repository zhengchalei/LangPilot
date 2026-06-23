class CorrectionResult {
  const CorrectionResult({
    required this.isAlreadyCorrect,
    required this.suggestions,
  });

  final bool isAlreadyCorrect;
  final List<CorrectionSuggestion> suggestions;

  factory CorrectionResult.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = json['suggestions'];
    final suggestions = rawSuggestions is List
        ? rawSuggestions
              .whereType<Map>()
              .map(
                (value) => CorrectionSuggestion.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where((suggestion) => suggestion.english.trim().isNotEmpty)
              .take(3)
              .toList(growable: false)
        : const <CorrectionSuggestion>[];

    return CorrectionResult(
      isAlreadyCorrect:
          json['isAlreadyCorrect'] == true || json['alreadyCorrect'] == true,
      suggestions: suggestions,
    );
  }
}

class CorrectionSuggestion {
  const CorrectionSuggestion({
    required this.title,
    required this.english,
    required this.chineseExplanation,
    required this.changes,
  });

  final String title;
  final String english;
  final String chineseExplanation;
  final List<String> changes;

  factory CorrectionSuggestion.fromJson(Map<String, dynamic> json) {
    return CorrectionSuggestion(
      title: _readString(json['title'], fallback: 'Recommended expression'),
      english: _readString(json['english']),
      chineseExplanation: _readString(
        json['chineseExplanation'] ?? json['explanationZh'],
      ),
      changes: _readStringList(json['changes']),
    );
  }

  static String _readString(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}
