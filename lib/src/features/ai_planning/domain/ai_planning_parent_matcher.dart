import '../../board/domain/models/work_item_type.dart';
import 'ai_planning_draft.dart';

/// Resolves a clearly named existing branch before asking the model to plan.
///
/// Matching locally makes placement deterministic: once a parent is selected,
/// the parser and commit service both require the generated roots to remain
/// below that exact item.
class AiPlanningParentMatcher {
  const AiPlanningParentMatcher._();

  static String? bestParentId({
    required String prompt,
    required Iterable<AiPlanningExistingItem> items,
  }) {
    final normalizedPrompt = _normalize(prompt);
    final promptTokens = _meaningfulTokens(normalizedPrompt).toSet();
    if (promptTokens.isEmpty) return null;

    final promptTypeCues = {
      for (final type in WorkItemType.values)
        if (promptTokens.contains(type.name)) type,
    };
    final matches = <_ParentMatch>[];
    for (final item in items) {
      if (item.type == WorkItemType.action) continue;
      final normalizedTitle = _normalize(item.title);
      final titleTokens = _meaningfulTokens(normalizedTitle)
          .where((token) => token != item.type.name)
          .toSet();
      if (titleTokens.isEmpty) continue;

      final phraseMatch = _containsPhrase(normalizedPrompt, normalizedTitle) ||
          _containsPhrase(
            normalizedPrompt,
            titleTokens.join(' '),
          );
      final matchingTokenCount = titleTokens.intersection(promptTokens).length;
      final allTitleTokensMatch = matchingTokenCount == titleTokens.length;
      final confidentTokenMatch = allTitleTokensMatch &&
          (titleTokens.length >= 2 || titleTokens.first.length >= 5);
      if (!phraseMatch && !confidentTokenMatch) continue;

      var score = phraseMatch ? 1000 : 700;
      score += titleTokens.length * 60;
      score += normalizedTitle.length;
      if (promptTypeCues.contains(item.type)) score += 120;
      if (item.type == WorkItemType.goal && promptTokens.contains('goal')) {
        score += 80;
      }
      matches.add(_ParentMatch(item.itemId, score));
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.first.itemId;
  }

  static String _normalize(String value) {
    final rawTokens = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'));
    return rawTokens
        .where((token) => token.isNotEmpty)
        .map(_canonical)
        .join(' ');
  }

  static Iterable<String> _meaningfulTokens(String normalized) sync* {
    for (final token in normalized.split(' ')) {
      if (token.isEmpty || _stopWords.contains(token)) continue;
      yield token;
    }
  }

  static String _canonical(String token) {
    if (token == 'house' || token == 'household') return 'home';
    if (token == 'maintaining' || token == 'maintain') return 'maintenance';
    if (token.length > 5 && token.endsWith('ies')) {
      return '${token.substring(0, token.length - 3)}y';
    }
    if (token.length > 4 && token.endsWith('s') && !token.endsWith('ss')) {
      return token.substring(0, token.length - 1);
    }
    return token;
  }

  static bool _containsPhrase(String text, String phrase) =>
      ' $text '.contains(' $phrase ');

  static const _stopWords = <String>{
    'a',
    'an',
    'and',
    'as',
    'at',
    'board',
    'current',
    'existing',
    'for',
    'in',
    'into',
    'my',
    'of',
    'on',
    'our',
    'plan',
    'planning',
    'the',
    'to',
    'under',
    'within',
  };
}

class _ParentMatch {
  const _ParentMatch(this.itemId, this.score);

  final String itemId;
  final int score;
}
