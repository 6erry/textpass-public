import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/review.dart';

class ReviewDetailScreen extends StatelessWidget {
  final Review review;

  const ReviewDetailScreen({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('口コミ詳細')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 24),
                const SizedBox(width: 4),
                Text(
                  review.rating.toString(),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${review.year}年度',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tags Section
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(
                    review.difficulty == 'easy'
                        ? '楽単'
                        : review.difficulty == 'hard'
                            ? '鬼単'
                            : '普通',
                    review.difficulty == 'easy'
                        ? Colors.green
                        : review.difficulty == 'hard'
                            ? Colors.red
                            : Colors.grey),
                _buildTag(review.hasTest ? 'テスト有' : 'テスト無',
                    review.hasTest ? Colors.orange : Colors.blueGrey),
                _buildTag(review.hasReport ? '課題有' : '課題無',
                    review.hasReport ? Colors.orange : Colors.blueGrey),
                _buildTag(_attendanceLabel(review.attendance), Colors.blue),
                _buildTag(review.textbook == 'required' ? '教科書必須' : '教科書不要',
                    review.textbook == 'required' ? Colors.red : Colors.green),
              ],
            ),
            const SizedBox(height: 24),

            // Comment Section
            const Text(
              'コメント',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                review.comment,
                style: const TextStyle(height: 1.6, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '投稿日: ${DateFormat('yyyy/MM/dd').format(review.createdAt)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _attendanceLabel(String val) {
    switch (val) {
      case 'always':
        return '出席重視';
      case 'sometimes':
        return '出席たまに';
      case 'none':
        return '出席なし';
      default:
        return '出席不明';
    }
  }
}
