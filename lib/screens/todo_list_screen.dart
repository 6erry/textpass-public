import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../widgets/contact_email_verification_dialog.dart';
import '../utils/todo_helper.dart';
import 'transaction_screen.dart';

class TodoListScreen extends StatelessWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('やることリスト'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final userDoc = snapshot.data?.data();
          final contactEmail =
              userDoc?['contactEmail'] as String? ?? user.email!;
          final isContactVerified = userDoc?['isContactEmailVerified'] as bool?;

          bool needsVerification;
          if (isContactVerified != null) {
            needsVerification = !isContactVerified;
          } else {
            needsVerification = !user.emailVerified;
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '今日の確認事項',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                // 1. Email Verification Task
                if (needsVerification)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.mail_outline,
                            color: Colors.orange.shade700, size: 20),
                      ),
                      title: const Text(
                        '連絡用メールアドレスを認証',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('$contactEmail の認証が未完了です。'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      onTap: () {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => ContactEmailVerificationDialog(
                            contactEmail: contactEmail,
                          ),
                        );
                      },
                    ),
                  ),

                // 2. Transaction Tasks
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .where('participants', arrayContains: user.uid)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final taskCandidates = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return TodoHelper.hasTask(data, user.uid);
                    }).toList();

                    return FutureBuilder<List<QueryDocumentSnapshot>>(
                      future: _visibleTaskDocs(taskCandidates),
                      builder: (context, visibleSnapshot) {
                        final tasks = visibleSnapshot.data ?? [];

                        if (tasks.isEmpty) {
                          if (!needsVerification) {
                            return const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: Text('現在対応が必要な項目はありません',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: tasks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _TodoItem(
                              chatRoomId: tasks[index].id,
                              data: tasks[index].data() as Map<String, dynamic>,
                              currentUserId: user.uid,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<QueryDocumentSnapshot>> _visibleTaskDocs(
      List<QueryDocumentSnapshot> docs) async {
    final visible = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final bookExists = data['bookExists'] as bool?;
      if (bookExists == true) {
        visible.add(doc);
        continue;
      }
      if (bookExists == false) continue;
      final bookId = data['bookId'] as String?;
      if (bookId == null || bookId.isEmpty) continue;
      final bookDoc = await FirebaseFirestore.instance
          .collection('books')
          .doc(bookId)
          .get();
      if (bookDoc.exists) visible.add(doc);
    }
    return visible;
  }
}

class _TodoItem extends StatelessWidget {
  const _TodoItem({
    required this.chatRoomId,
    required this.data,
    required this.currentUserId,
  });

  final String chatRoomId;
  final Map<String, dynamic> data;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final bookId = data['bookId'] as String;
    final isBuyer = currentUserId == data['buyerId'];
    return _buildTile(context, bookId, isBuyer, data);
  }

  Widget _buildTile(BuildContext context, String bookId, bool isBuyer,
      Map<String, dynamic> data) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('books').doc(bookId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final bookData = snapshot.data!.data() as Map<String, dynamic>?;
        if (bookData == null) return const SizedBox.shrink();

        final book = Book.fromFirestore(snapshot.data!);
        final title = book.title;
        final thumbnailUrl =
            book.imageUrls.isNotEmpty ? book.imageUrls.first : null;

        String message =
            TodoHelper.getTaskMessage(data, currentUserId, title, isBuyer);
        final status = data['status'] as String? ?? 'paid';
        final taskTitle = TodoHelper.getTaskTitle(data, currentUserId);
        final meta = TodoHelper.getTaskMeta(data);

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TransactionScreen(
                    chatRoomId: chatRoomId,
                    book: book,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  thumbnailUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            thumbnailUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => _buildFallbackThumb(),
                          ),
                        )
                      : _buildFallbackThumb(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                taskTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            _TaskBadge(
                              label: status == 'completed' ? '評価' : '取引',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                meta,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatDate(data['createdAt'] as Timestamp?),
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackThumb() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.menu_book_outlined, color: Colors.grey.shade500),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 0) {
      return '${diff.inDays}日前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}時間前';
    } else {
      return '${diff.inMinutes}分前';
    }
  }
}

class _TaskBadge extends StatelessWidget {
  const _TaskBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
