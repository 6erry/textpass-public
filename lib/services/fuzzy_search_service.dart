import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:string_similarity/string_similarity.dart';

class FuzzySearchService {
  // Cache candidates to reduce Firestore reads
  List<String> _cachedCandidates = [];
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 30);

  Future<String?> findClosestMatch(String query) async {
    if (query.isEmpty) return null;

    final candidates = await _getCandidates();
    if (candidates.isEmpty) return null;

    final bestMatch = StringSimilarity.findBestMatch(query, candidates);

    // Threshold for suggestion (0.0 to 1.0)
    // 0.3 is a reasonable starting point for "somewhat similar"
    if ((bestMatch.bestMatch.rating ?? 0.0) > 0.3) {
      return bestMatch.bestMatch.target;
    }

    return null;
  }

  Future<List<String>> _getCandidates() async {
    // Return cached if valid
    if (_cachedCandidates.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedCandidates;
    }

    try {
      // Fetch recent 100 book titles
      final snapshot = await FirebaseFirestore.instance
          .collection('books')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final titles = snapshot.docs
          .map((doc) => doc.data()['title'] as String?)
          .where((title) => title != null && title.isNotEmpty)
          .map((title) => title!)
          .toSet() // Remove duplicates
          .toList();

      _cachedCandidates = titles;
      _lastFetchTime = DateTime.now();
      return titles;
    } catch (e) {
      // debugPrint('Error fetching fuzzy search candidates: $e');
      return [];
    }
  }
}
