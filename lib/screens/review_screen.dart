import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:textpass/utils/app_toast.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.transactionId,
    required this.revieweeId,
  });

  final String transactionId;
  final String revieweeId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('評価を入力'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '取引はいかがでしたか？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return IconButton(
                    onPressed: () {
                      setState(() {
                        _rating = index + 1;
                      });
                    },
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'コメント（任意）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '取引の感想や相手へのメッセージを入力してください',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        '評価を送信する',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.transactionId)
          .get();

      String reviewType = 'unknown';
      if (chatDoc.exists) {
        final data = chatDoc.data()!;
        final buyerId = data['buyerId'] as String?;
        if (buyerId == user.uid) {
          reviewType =
              'buyer'; // Review written *by* the buyer (about the seller)
        } else {
          reviewType =
              'seller'; // Review written *by* the seller (about the buyer)
        }
      }

      final batch = FirebaseFirestore.instance.batch();

      // 1. Add review document
      final reviewRef = FirebaseFirestore.instance.collection('reviews').doc();
      batch.set(reviewRef, {
        'transactionId': widget.transactionId,
        'reviewerId': user.uid,
        'revieweeId': widget.revieweeId,
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'reviewType': reviewType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Remove user from pendingReviews in chat_rooms so the Todo task clears properly
      final chatRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.transactionId); // transactionId is the chatRoomId
      batch.update(chatRef, {
        'pendingReviews': FieldValue.arrayRemove([user.uid])
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true); // Return true to indicate success
      AppToast.show(context, '評価を送信しました！');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '送信に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}
