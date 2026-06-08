import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'stripe_service.dart';

class TransactionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Request a cancellation for a transaction.
  Future<void> requestCancellation({
    required String chatRoomId,
    required String reason,
    String? description,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'cancellationStatus': 'requesting',
      'cancellationRequesterId': uid,
      'cancellationReason': reason,
      'cancellationDescription': description,
      'cancellationRequestedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Approve a cancellation request.
  /// This triggers a refund via Stripe and updates the transaction status.
  Future<void> approveCancellation({
    required String chatRoomId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    try {
      await StripeService().refundTransaction(chatRoomId);
    } catch (e) {
      throw Exception('Refund failed: $e');
    }
  }

  /// Reject a cancellation request.
  Future<void> rejectCancellation(String chatRoomId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'cancellationStatus': FieldValue.delete(),
      'cancellationRequesterId': FieldValue.delete(),
      'cancellationReason': FieldValue.delete(),
      'cancellationDescription': FieldValue.delete(),
      'cancellationRequestedAt': FieldValue.delete(),
    });
  }
}
