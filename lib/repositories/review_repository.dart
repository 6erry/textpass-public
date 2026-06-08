import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/review.dart';

final reviewRepositoryProvider = Provider((ref) => ReviewRepository());

class ReviewRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<bool> _canAccessClassReviews() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return false;
    final isStudentVerified = data['isStudentVerified'] as bool? ?? false;
    final hasUniversityIdentity =
        (data['universityId'] as String?)?.isNotEmpty == true ||
            (data['universityEmail'] as String?)?.isNotEmpty == true;
    return isStudentVerified || (user.emailVerified && hasUniversityIdentity);
  }

  // Post a review
  Future<void> addReview(Review review) async {
    if (!await _canAccessClassReviews()) {
      throw Exception('レビュー投稿には大学メール認証が必要です。');
    }
    await _firestore.collection('class_reviews').add(review.toMap());
  }

  Stream<List<Review>> getReviewsForClass(
    String title,
    String teacher, {
    String? classKey,
  }) {
    return Stream.fromFuture(_canAccessClassReviews()).asyncExpand((allowed) {
      if (!allowed) return Stream.value(<Review>[]);
      return _getReviewsForClassQuery(title, teacher, classKey: classKey);
    });
  }

  Stream<List<Review>> _getReviewsForClassQuery(
    String title,
    String teacher, {
    String? classKey,
  }) {
    final normalizedKey = classKey?.trim() ?? '';
    final query = normalizedKey.isNotEmpty
        ? _firestore
            .collection('class_reviews')
            .where('classKey', isEqualTo: normalizedKey)
        : _firestore
            .collection('class_reviews')
            .where('title', isEqualTo: title)
            .where('teacher', isEqualTo: teacher);

    return query.snapshots().asyncMap((snapshot) async {
      final reviews = <Review>[
        ...snapshot.docs.map((doc) => Review.fromFirestore(doc)),
      ];

      if (normalizedKey.isNotEmpty) {
        final legacySnapshot = await _firestore
            .collection('class_reviews')
            .where('title', isEqualTo: title)
            .where('teacher', isEqualTo: teacher)
            .get();
        final seenIds = reviews.map((review) => review.id).toSet();
        for (final doc in legacySnapshot.docs) {
          if (seenIds.add(doc.id)) {
            reviews.add(Review.fromFirestore(doc));
          }
        }
      }

      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    });
  }

  // Calculate average rating
  double calculateAverageRating(List<Review> reviews) {
    if (reviews.isEmpty) return 0.0;
    final sum = reviews.fold(0.0, (prev, review) => prev + review.rating);
    return double.parse((sum / reviews.length).toStringAsFixed(1));
  }

  // Flexible Search: Partial match & Multi-keyword
  Future<List<Review>> searchReviews(String query) async {
    if (query.isEmpty) return [];
    if (!await _canAccessClassReviews()) return [];

    // Fetch all reviews (Limited to recent 500 for performance safety if needed, strict 'limit' not applied yet)
    // For substring match, we MUST fetch data first as Firestore doesn't support 'LIKE %...%'
    final snapshot = await _firestore
        .collection('class_reviews')
        .orderBy('createdAt', descending: true)
        .limit(200) // Safety limit for MVP
        .get();

    final allReviews =
        snapshot.docs.map((doc) => Review.fromFirestore(doc)).toList();

    final keywords = query.trim().replaceAll('　', ' ').split(RegExp(r'\s+'));

    return allReviews.where((review) {
      return keywords.every((keyword) {
        final kw = keyword.toLowerCase();
        return review.title.toLowerCase().contains(kw) ||
            review.teacher.toLowerCase().contains(kw) ||
            review.comment.toLowerCase().contains(kw) ||
            review.classKey.toLowerCase().contains(kw);
      });
    }).toList();
  }

  // Check if user has already reviewed this class
  Future<bool> hasUserReviewed(
    String userId,
    String title,
    String teacher, {
    String? classKey,
  }) async {
    if (!await _canAccessClassReviews()) return false;

    final normalizedKey = classKey?.trim() ?? '';
    if (normalizedKey.isNotEmpty) {
      final byClassKey = await _firestore
          .collection('class_reviews')
          .where('userId', isEqualTo: userId)
          .where('classKey', isEqualTo: normalizedKey)
          .limit(1)
          .get();
      if (byClassKey.docs.isNotEmpty) return true;
    }

    final legacySnapshot = await _firestore
        .collection('class_reviews')
        .where('userId', isEqualTo: userId)
        .where('title', isEqualTo: title)
        .where('teacher', isEqualTo: teacher)
        .limit(1)
        .get();
    return legacySnapshot.docs.isNotEmpty;
  }

  // Get recent reviews (Stream)
  Stream<List<Review>> getRecentReviews({int limit = 10}) {
    return Stream.fromFuture(_canAccessClassReviews()).asyncExpand((allowed) {
      if (!allowed) return Stream.value(<Review>[]);
      return _firestore
          .collection('class_reviews')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => Review.fromFirestore(doc)).toList();
      });
    });
  }
}
