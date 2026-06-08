import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReviewsListScreen extends StatelessWidget {
  const ReviewsListScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('レビュー一覧'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '出品者としての評価'), // Reviews from buyers
              Tab(text: '購入者としての評価'), // Reviews from sellers
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReviewListTab(userId: userId, reviewType: 'buyer'),
            _ReviewListTab(userId: userId, reviewType: 'seller'),
          ],
        ),
      ),
    );
  }
}

class _ReviewListTab extends StatelessWidget {
  const _ReviewListTab({required this.userId, required this.reviewType});

  final String userId;
  final String reviewType;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .where('reviewType', isEqualTo: reviewType)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Review List Error: ${snapshot.error}');
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('エラー: ${snapshot.error}'),
          ));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data?.docs.toList() ?? [];

        // Sort descending by createdAt in memory to avoid needing a composite index
        docs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        if (docs.isEmpty) {
          return const Center(child: Text('まだレビューはありません'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            return _ReviewCard(data: data);
          },
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final comment = data['comment'] as String? ?? '';
    final reviewerId = data['reviewerId'] as String? ?? '';
    final reviewerName = data['reviewerName'] as String? ?? '';
    final timestamp = data['createdAt'];

    DateTime? createdAt;
    if (timestamp is Timestamp) {
      createdAt = timestamp.toDate();
    }

    final dateLabel = createdAt == null
        ? ''
        : DateFormat('yyyy/MM/dd HH:mm').format(createdAt);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ...List.generate(5, (index) {
                  final starIndex = index + 1;
                  if (rating >= starIndex) {
                    return const Icon(Icons.star,
                        color: Colors.amber, size: 20);
                  }
                  if (rating >= starIndex - 0.5) {
                    return const Icon(Icons.star_half,
                        color: Colors.amber, size: 20);
                  }
                  return const Icon(Icons.star_border,
                      color: Colors.amber, size: 20);
                }),
                const SizedBox(width: 8),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  dateLabel,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (comment.isNotEmpty) ...[
              Text(
                comment,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: _ReviewerName(
                    reviewerId: reviewerId,
                    fallbackName: reviewerName,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewerName extends StatelessWidget {
  const _ReviewerName({required this.reviewerId, required this.fallbackName});

  final String reviewerId;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    if (fallbackName.isNotEmpty) {
      return Text(
        fallbackName,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        overflow: TextOverflow.ellipsis,
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('users').doc(reviewerId).get(),
      builder: (context, snapshot) {
        final name = snapshot.data?.data()?['displayName'] as String?;
        return Text(
          name ?? 'ユーザー',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
