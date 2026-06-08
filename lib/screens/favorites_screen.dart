import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../widgets/book_card.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入り一覧'),
      ),
      body: user == null
          ? const Center(
              child: Text('お気に入りを表示するにはログインしてください。'),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Text('お気に入り情報の取得に失敗しました。'),
                  );
                }

                final data = snapshot.data?.data();
                final favoriteBookIds =
                    (data?['favoriteBookIds'] as List<dynamic>? ?? const [])
                        .map((id) => id.toString())
                        .toList();

                if (favoriteBookIds.isEmpty) {
                  return const Center(
                    child: Text('お気に入りに登録した本はありません'),
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('books')
                      .where(FieldPath.documentId, whereIn: favoriteBookIds)
                      .snapshots(),
                  builder: (context, booksSnapshot) {
                    if (booksSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (booksSnapshot.hasError) {
                      return const Center(
                        child: Text('お気に入りの本の取得に失敗しました。'),
                      );
                    }

                    final docs = booksSnapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('お気に入りに登録した本はありません'),
                      );
                    }

                    final books = docs.map((doc) {
                      return Book.fromFirestore(doc);
                    }).toList();

                    return GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return BookCard(book: book);
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
