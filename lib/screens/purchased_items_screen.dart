import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../widgets/empty_state_widget.dart';
import 'book_detail_screen.dart';

class PurchasedItemsScreen extends StatelessWidget {
  const PurchasedItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('購入した商品'),
      ),
      body: user == null
          ? const Center(
              child: Text('購入履歴を確認するにはログインしてください。'),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .where('buyerId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          const Text('購入履歴の取得に失敗しました。',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SelectableText(
                            'エラー詳細: ${snapshot.error}',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return EmptyStateWidget(
                    icon: Icons.shopping_bag_outlined,
                    title: '購入履歴はありません',
                    message: 'まだ商品を購入していません。',
                    buttonText: '商品を探す',
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final bookId = data['bookId'] as String?;

                    if (bookId == null || bookId.isEmpty) {
                      return const ListTile(
                        title: Text('不明な商品'),
                      );
                    }

                    return FutureBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .collection('books')
                          .doc(bookId)
                          .get(),
                      builder: (context, bookSnapshot) {
                        if (bookSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const ListTile(
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            title: Text('読み込み中'),
                          );
                        }

                        if (bookSnapshot.hasError ||
                            !bookSnapshot.hasData ||
                            !bookSnapshot.data!.exists) {
                          return const ListTile(
                            leading: Icon(Icons.error_outline),
                            title: Text('商品情報を取得できませんでした'),
                          );
                        }

                        final book = Book.fromFirestore(bookSnapshot.data!);
                        final bookData = bookSnapshot.data!.data()!;
                        final title = bookData['title'] as String? ?? '不明な書籍';
                        final imageUrl = bookData['imageUrl'] as String? ?? '';
                        final priceRaw = bookData['price'];
                        final price = priceRaw is int ? priceRaw : 0;

                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 48,
                                      height: 48,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image,
                                          size: 24, color: Colors.grey),
                                    ),
                                  )
                                : Container(
                                    width: 48,
                                    height: 48,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image,
                                        size: 24, color: Colors.grey),
                                  ),
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '¥$price',
                            style: const TextStyle(color: Colors.red),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    BookDetailScreen(book: book),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
