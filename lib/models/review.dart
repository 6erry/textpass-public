import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/class_identity.dart';
import '../utils/japanese_display_text.dart';

class Review {
  final String id;
  final String userId;
  final String title; // Class name
  final String teacher;
  final String classKey;
  final int year;
  final double rating; // 1.0 - 5.0
  final String difficulty; // 'easy', 'normal', 'hard'
  final bool hasTest;
  final bool hasReport;
  final String attendance; // 'always', 'sometimes', 'none'
  final String textbook; // 'required', 'not_needed'
  final String comment;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.userId,
    required this.title,
    required this.teacher,
    required this.year,
    required this.rating,
    required this.difficulty,
    required this.hasTest,
    required this.hasReport,
    required this.attendance,
    required this.textbook,
    required this.comment,
    required this.createdAt,
    String? classKey,
  }) : classKey = classKey ??
            buildClassKey(
              universityId: 'hokudai.ac.jp',
              title: title,
              teacher: teacher,
            );

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: displayJapanesePrimaryText(data['title']?.toString() ?? ''),
      teacher: displayJapanesePrimaryText(data['teacher']?.toString() ?? ''),
      classKey: data['classKey'] ?? data['class_key'],
      year: data['year'] ?? 2025,
      rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      difficulty: data['difficulty'] ?? 'normal',
      hasTest: data['hasTest'] ?? false,
      hasReport: data['hasReport'] ?? false,
      attendance: data['attendance'] ?? 'none',
      textbook: data['textbook'] ?? 'not_needed',
      comment: data['comment'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'teacher': teacher,
      'classKey': classKey,
      'class_key': classKey,
      'year': year,
      'rating': rating,
      'difficulty': difficulty,
      'hasTest': hasTest,
      'hasReport': hasReport,
      'attendance': attendance,
      'textbook': textbook,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
