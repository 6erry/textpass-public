import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/review_repository.dart';
import '../models/review.dart';
import '../models/user_class.dart';
import 'class_detail_screen.dart';

final reviewSearchQueryProvider = StateProvider<String>((ref) => '');

final reviewSearchResultsProvider =
    FutureProvider.autoDispose<List<Review>>((ref) async {
  final query = ref.watch(reviewSearchQueryProvider);
  if (query.isEmpty) return [];
  return ref.read(reviewRepositoryProvider).searchReviews(query);
});

class ReviewSearchScreen extends ConsumerWidget {
  const ReviewSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(reviewSearchQueryProvider);
    final resultsAsync = ref.watch(reviewSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '講義名や教員名で検索',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          style: const TextStyle(fontSize: 18),
          onChanged: (val) {
            // Debounce could be added here if needed, but for now direct update
            ref.read(reviewSearchQueryProvider.notifier).state = val;
          },
        ),
      ),
      body: resultsAsync.when(
        data: (reviews) {
          if (query.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('講義名または教員名で検索', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          if (reviews.isEmpty) {
            return const Center(child: Text('見つかりませんでした'));
          }

          final grouped = <String, List<Review>>{};
          for (var r in reviews) {
            final key = r.classKey.isNotEmpty
                ? r.classKey
                : '${r.title}___${r.teacher}';
            if (!grouped.containsKey(key)) grouped[key] = [];
            grouped[key]!.add(r);
          }

          final keys = grouped.keys.toList();

          return ListView.builder(
            itemCount: keys.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final key = keys[index];
              final groupReviews = grouped[key]!;
              final first = groupReviews.first;

              final avg = ref
                  .read(reviewRepositoryProvider)
                  .calculateAverageRating(groupReviews);

              final hasEasy = groupReviews.any((r) => r.difficulty == 'easy');
              final hasHard = groupReviews.any((r) => r.difficulty == 'hard');

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  title: Text(first.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle:
                      Text('${first.teacher}  (レビュー${groupReviews.length}件)'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          Text(avg.toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (hasEasy)
                        const Text('楽単あり',
                            style: TextStyle(color: Colors.green, fontSize: 10))
                      else if (hasHard)
                        const Text('鬼単あり',
                            style: TextStyle(color: Colors.red, fontSize: 10)),
                    ],
                  ),
                  onTap: () {
                    final dummyClass = UserClass(
                      id: 'preview_review',
                      title: first.title,
                      teacher: first.teacher,
                      room: '',
                      day: '',
                      period: 1,
                      colorValue: Colors.blue.toARGB32(),
                      textbook: '',
                      semester: '',
                      year: first.year,
                      classKey: first.classKey,
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClassDetailScreen(userClass: dummyClass),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }
}
