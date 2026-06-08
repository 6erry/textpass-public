import 'package:cloud_firestore/cloud_firestore.dart';

class ClassReminder {
  final String id;
  final String title;
  final DateTime notifyAt;
  final bool isRecurring;
  final int notificationId;

  ClassReminder({
    required this.id,
    required this.title,
    required this.notifyAt,
    required this.isRecurring,
    required this.notificationId,
  });

  factory ClassReminder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClassReminder(
      id: doc.id,
      title: data['title'] ?? '',
      notifyAt: (data['notifyAt'] as Timestamp).toDate(),
      isRecurring: data['isRecurring'] ?? false,
      notificationId: data['notificationId'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'notifyAt': Timestamp.fromDate(notifyAt),
      'isRecurring': isRecurring,
      'notificationId': notificationId,
    };
  }
}
