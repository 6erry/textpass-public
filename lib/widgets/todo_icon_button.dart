import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/todo_list_screen.dart';
import '../utils/todo_helper.dart';

class TodoIconButton extends StatelessWidget {
  const TodoIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.check_circle_outline, color: Colors.black87),
        tooltip: 'ToDo',
        onPressed: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TodoListScreen()));
        },
      );
    }

    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          icon: const Icon(Icons.check_circle_outline, color: Colors.black87),
          tooltip: 'ToDo',
          onPressed: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TodoListScreen()));
          },
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            // Check 1: Email Verification
            final userData = userSnapshot.data?.data();
            final isContactVerified =
                userData?['isContactEmailVerified'] as bool?;
            final hasEmailTask = isContactVerified != null
                ? !isContactVerified
                : !user.emailVerified;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .where('participants', arrayContains: user.uid)
                  .snapshots(), // Get all to filter locally or query active ones?
              // Querying locally is safer for limits if list isn't huge.
              builder: (context, roomSnapshot) {
                final docs = roomSnapshot.data?.docs ?? [];
                return FutureBuilder<int>(
                  future: _visibleTransactionTaskCount(docs, user.uid),
                  builder: (context, countSnapshot) {
                    final activeCount =
                        (countSnapshot.data ?? 0) + (hasEmailTask ? 1 : 0);
                    if (activeCount == 0) return const SizedBox.shrink();

                    return Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<int> _visibleTransactionTaskCount(
    List<QueryDocumentSnapshot> docs,
    String uid,
  ) async {
    int count = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!TodoHelper.hasTask(data, uid)) continue;
      final bookExists = data['bookExists'] as bool?;
      if (bookExists == true) {
        count++;
        continue;
      }
      if (bookExists == false) continue;
      final bookId = data['bookId'] as String?;
      if (bookId == null || bookId.isEmpty) continue;
      final bookDoc = await FirebaseFirestore.instance
          .collection('books')
          .doc(bookId)
          .get();
      if (bookDoc.exists) count++;
    }
    return count;
  }
}
