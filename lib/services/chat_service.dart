import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> sendMessage({
    required String chatRoomId,
    required String text,
    required String peerUid,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // 1. Add message to chat room
    await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'text': text,
      'senderId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Send notification to peer
    // Don't await this to avoid blocking the UI if it fails or takes time
    _sendNotificationToPeer(
      peerUid: peerUid,
      text: text,
      chatRoomId: chatRoomId,
      senderName: user.displayName ?? 'ユーザー',
    ).catchError((e) {
      // print('Error sending notification: $e');
    });
  }

  Future<void> _sendNotificationToPeer({
    required String peerUid,
    required String text,
    required String chatRoomId,
    required String senderName,
  }) async {
    await _firestore
        .collection('users')
        .doc(peerUid)
        .collection('notifications')
        .add({
      'type': 'message',
      'title': '新着メッセージ',
      'body': '$senderNameさんからメッセージが届きました',
      'relatedId': chatRoomId,
      'fromUid': _auth.currentUser!.uid,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
