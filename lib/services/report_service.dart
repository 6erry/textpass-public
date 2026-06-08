import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> submitReport({
    required String type, // 'item', 'user', 'transaction'
    required String reason,
    String? targetUserId,
    String? targetBookId,
    String? transactionId,
    String? description,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    await _firestore.collection('reports').add({
      'reporterId': user.uid,
      'reporterUserId': user.uid,
      'targetType': _targetTypeFromLegacy(type),
      'targetId': targetBookId ?? targetUserId ?? transactionId,
      'type': type,
      'reason': reason,
      'targetUserId': targetUserId,
      'targetBookId': targetBookId,
      'reportedUserId': targetUserId,
      'bookId': targetBookId,
      'transactionId': transactionId,
      'detail': description,
      'description': description,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitContentReport({
    required String targetType,
    required String targetId,
    required String reason,
    String? detail,
    String? universityId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    await _firestore.collection('reports').add({
      'reporterId': user.uid,
      'reporterUserId': user.uid,
      'targetType': targetType,
      'targetId': targetId,
      'type': targetType == 'book' ? 'listing' : targetType,
      'reason': reason,
      'detail': detail,
      'description': detail,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (universityId != null) 'universityId': universityId,
      if (targetType == 'book') 'targetBookId': targetId,
      if (targetType == 'event') 'targetEventId': targetId,
      if (targetType == 'circle') 'targetCircleId': targetId,
      if (targetType == 'chat') 'transactionId': targetId,
    });
  }

  String _targetTypeFromLegacy(String type) {
    switch (type) {
      case 'item':
      case 'listing':
        return 'book';
      case 'transaction':
        return 'chat';
      default:
        return type;
    }
  }
}
