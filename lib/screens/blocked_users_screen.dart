import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:textpass/utils/app_toast.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  Future<void> _unblock(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'blockedUserIds': FieldValue.arrayRemove([uid])
      },
      SetOptions(merge: true),
    );
    if (!mounted) return;
    AppToast.show(context, 'ブロックを解除しました');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインしてください')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ブロックしたユーザー')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final blocked =
              List<String>.from(snapshot.data?.data()?['blockedUserIds'] ?? []);
          if (blocked.isEmpty) {
            return const Center(child: Text('ブロック中のユーザーはいません'));
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: blocked.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final blockedId = blocked[index];
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(blockedId)
                    .get(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: CircularProgressIndicator(),
                      title: Text('読み込み中'),
                    );
                  }
                  final docData = snap.data;
                  if (docData == null || !docData.exists) {
                    return ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('不明なユーザー'),
                      subtitle: Text(blockedId,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(
                        onPressed: () => _unblock(blockedId),
                        child: const Text('解除'),
                      ),
                    );
                  }

                  final data = docData.data();
                  final name = data?['displayName'] as String? ?? '不明なユーザー';
                  return ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(blockedId,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: () => _unblock(blockedId),
                      child: const Text('解除'),
                    ),
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
