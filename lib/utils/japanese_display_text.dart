String displayJapanesePrimaryText(String value) {
  final text =
      value.replaceAll('　', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || !_containsJapanese(text)) return text;

  final splitIndex = _firstTrailingEnglishBlockIndex(text);
  if (splitIndex == null) return text;

  final candidate = text.substring(0, splitIndex).trim();
  return candidate.isEmpty ? text : candidate;
}

bool _containsJapanese(String value) {
  return RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(value);
}

int? _firstTrailingEnglishBlockIndex(String value) {
  final matches =
      RegExp(r'\s[A-Za-z][A-Za-z][A-Za-z0-9()&.,:/+\- ]*$').allMatches(value);
  for (final match in matches) {
    final before = value.substring(0, match.start).trim();
    final tail = value.substring(match.start).trim();
    if (before.isEmpty || tail.isEmpty) continue;
    if (_containsJapanese(before) && _looksLikeEnglishTail(tail)) {
      return match.start;
    }
  }
  return null;
}

bool _looksLikeEnglishTail(String value) {
  final letters = RegExp(r'[A-Za-z]').allMatches(value).length;
  if (letters < 3) return false;
  final japanese = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(value);
  return !japanese;
}
