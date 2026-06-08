import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/circle.dart';
import '../../services/circle_service.dart';
import 'package:textpass/utils/app_toast.dart';

class CircleMemberListScreen extends StatelessWidget {
  final Circle circle;

  const CircleMemberListScreen({super.key, required this.circle});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('メンバー確認'),
      ),
      body: Column(
        children: [
          if (circle.memberUids.length < 3)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'メンバーがあと${3 - circle.memberUids.length}人参加すると、サークル機能が有効になります',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('circles')
                  .doc(circle.id)
                  .snapshots(),
              builder: (context, circleSnapshot) {
                final currentCircle = circleSnapshot.data?.exists == true
                    ? Circle.fromFirestore(circleSnapshot.data!)
                    : circle;
                final canManageRoles = currentUid != null &&
                    currentCircle.canManageCircle(currentUid);

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('belonging_circle_id', isEqualTo: circle.id)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('メンバー情報を取得できませんでした'));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return const Center(child: Text('メンバーはいません'));
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final uid = docs[index].id;
                        final name = data['displayName'] ?? '名無しユーザー';
                        final faculty = data['faculty'] ?? '';
                        final grade = data['grade'] ?? '';
                        final photoUrl = data['photoUrl'];
                        final role = currentCircle.roleFor(uid);

                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey.shade100,
                              child: photoUrl != null
                                  ? Image.network(photoUrl, fit: BoxFit.cover)
                                  : const Icon(Icons.person,
                                      color: Colors.grey),
                            ),
                          ),
                          title: Text(name),
                          subtitle: Text(
                            [
                              role.label,
                              faculty,
                              grade,
                            ].where((e) => e.isNotEmpty).join(' / '),
                          ),
                          trailing: canManageRoles
                              ? PopupMenuButton<CircleMemberRole>(
                                  tooltip: 'ロールを変更',
                                  initialValue: role,
                                  onSelected: (selectedRole) async {
                                    try {
                                      await CircleService().updateMemberRole(
                                        circleId: circle.id,
                                        memberUid: uid,
                                        role: selectedRole,
                                      );
                                      if (context.mounted) {
                                        AppToast.show(context, 'ロールを更新しました');
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        AppToast.show(context, '$e');
                                      }
                                    }
                                  },
                                  itemBuilder: (context) {
                                    return CircleMemberRole.values.map((role) {
                                      return PopupMenuItem(
                                        value: role,
                                        child: Text(role.label),
                                      );
                                    }).toList();
                                  },
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    role.label,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
