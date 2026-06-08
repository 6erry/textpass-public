import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../widgets/empty_state_widget.dart';
import 'transaction_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('取引メッセージ一覧'),
      ),
      body: user == null
          ? const Center(
              child: Text('取引メッセージを確認するにはログインしてください'),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // final blockedUserIds = List<String>.from(
                //   userSnapshot.data?.data()?['blockedUserIds'] ?? [],
                // );

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .where('participants', arrayContains: user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('取引メッセージの取得に失敗しました'),
                      );
                    }

                    final docs =
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                      snapshot.data?.docs ?? const [],
                    );
                    if (docs.isEmpty) {
                      return const EmptyStateWidget(
                        icon: Icons.chat_bubble_outline,
                        title: 'メッセージはありません',
                        message: '気になる商品について質問したり、\n購入して取引を始めましょう。',
                      );
                    }

                    docs.sort((a, b) {
                      final aCreated = a.data()['createdAt'] as Timestamp?;
                      final bCreated = b.data()['createdAt'] as Timestamp?;
                      if (aCreated == null && bCreated == null) return 0;
                      if (aCreated == null) return 1;
                      if (bCreated == null) return -1;
                      return bCreated.compareTo(aCreated);
                    });

                    final filteredDocs =
                        docs; // Show all transactions even if blocked

                    if (filteredDocs.isEmpty) {
                      return const EmptyStateWidget(
                        icon: Icons.chat_bubble_outline,
                        title: 'メッセージはありません',
                        message: '気になる商品について質問したり、\n購入して取引を始めましょう。',
                      );
                    }

                    return ListView.separated(
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data();
                        final bookId = data['bookId'] as String?;

                        if (bookId == null || bookId.isEmpty) {
                          return const ListTile(
                            leading: Icon(Icons.chat_bubble_outline),
                            title: Text('不明な出品'),
                            trailing: Icon(Icons.arrow_forward_ios, size: 16),
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
                                leading: _LoadingThumbnail(
                                  isError: false,
                                  fallbackIcon: Icons.chat_bubble_outline,
                                ),
                                title: Text('読み込み中'),
                                trailing:
                                    Icon(Icons.arrow_forward_ios, size: 16),
                              );
                            }

                            if (bookSnapshot.hasError ||
                                !bookSnapshot.hasData ||
                                !bookSnapshot.data!.exists) {
                              return const ListTile(
                                leading: _LoadingThumbnail(
                                  isError: true,
                                  fallbackIcon: Icons.warning_amber_rounded,
                                ),
                                title: Text('商品情報を取得できませんでした'),
                                trailing:
                                    Icon(Icons.arrow_forward_ios, size: 16),
                              );
                            }

                            final book = Book.fromFirestore(bookSnapshot.data!);
                            final title = book.title;
                            final price = book.price;
                            final imageUrl = book.imageUrls.isNotEmpty
                                ? book.imageUrls.first
                                : '';

                            return ListTile(
                              leading: _Thumbnail(imageUrl: imageUrl),
                              title: Text(title),
                              subtitle: Text('¥$price'),
                              trailing:
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => _openChat(context, doc.id, book),
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

  void _openChat(BuildContext context, String chatRoomId, Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionScreen(
          chatRoomId: chatRoomId,
          book: book,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const _LoadingThumbnail(
        isError: false,
        fallbackIcon: Icons.menu_book_outlined,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _LoadingThumbnail(
          isError: true,
          fallbackIcon: Icons.menu_book_outlined,
        ),
      ),
    );
  }
}

class _LoadingThumbnail extends StatelessWidget {
  const _LoadingThumbnail({
    required this.isError,
    required this.fallbackIcon,
  });

  final bool isError;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        fallbackIcon,
        color: isError
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
