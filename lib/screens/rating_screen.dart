import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:textpass/utils/app_toast.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.chatRoomId});

  final String chatRoomId;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _rating = 0;
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
        title: const Text('取引を評価'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '取引の評価を選択してください。',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                final isActive = _rating >= starIndex;
                return IconButton(
                  icon: Icon(
                    isActive ? Icons.star : Icons.star_border,
                    color: isActive
                        ? Colors.amber
                        : Theme.of(context).colorScheme.outline,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = starIndex;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'コメント（任意）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '取引の感想や相手へのフィードバックを記入してください。',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReview,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('レビューを送信'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      AppToast.show(context, '星を選択してください。');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppToast.show(context, 'レビューを送信するにはログインしてください。');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .get();
      final chatData = chatDoc.data();

      if (chatData == null) {
        throw Exception('取引情報が見つかりませんでした。');
      }

      final buyerId = chatData['buyerId'] as String? ?? '';
      final sellerId = chatData['sellerId'] as String? ?? '';

      final reviewerId = currentUser.uid;
      late final String revieweeId;
      late final String reviewFlagField;
      late final String reviewType;

      if (reviewerId == buyerId) {
        revieweeId = sellerId;
        reviewFlagField = 'buyerRated';
        reviewType = 'buyer';
      } else if (reviewerId == sellerId) {
        revieweeId = buyerId;
        reviewFlagField = 'sellerRated';
        reviewType = 'seller';
      } else {
        throw Exception('この取引に参加していません。');
      }

      final reviewerName = currentUser.displayName ?? '';
      final batch = FirebaseFirestore.instance.batch();
      final reviewRef = FirebaseFirestore.instance.collection('reviews').doc();

      batch.set(reviewRef, {
        'chatRoomId': widget.chatRoomId,
        'transactionId': widget.chatRoomId,
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'reviewerId': reviewerId,
        'reviewerName': reviewerName,
        'revieweeId': revieweeId,
        'reviewType': reviewType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(chatDoc.reference, {
        reviewFlagField: true,
        'pendingReviews': FieldValue.arrayRemove([reviewerId]),
      });

      await batch.commit();

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      AppToast.show(context, e.toString());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      AppToast.show(context, 'レビューの送信に失敗しました。');
    }
  }
}
