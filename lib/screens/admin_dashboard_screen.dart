import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:textpass/utils/app_toast.dart';
import '../widgets/app_custom_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  static const List<String> adminUids = [
    'ADMIN_UID_PLACEHOLDER',
    'uryu_s_uid_here', // Add your UID here for testing
  ];

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool get _isAdmin {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && AdminDashboardScreen.adminUids.contains(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理者ダッシュボード')),
        body: const Center(child: Text('アクセス権限がありません')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('管理者ダッシュボード')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('通報はありません'));
          }

          final reports = snapshot.data!.docs;

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final data = report.data() as Map<String, dynamic>;
              return _ReportCard(reportId: report.id, data: data);
            },
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.reportId, required this.data});

  final String reportId;
  final Map<String, dynamic> data;

  Future<void> _resolveReport(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(reportId)
        .update({'status': 'resolved'});
    if (context.mounted) {
      AppToast.showSuccess(context, '解決済みにしました');
    }
  }

  Future<void> _banUser(BuildContext context, String userId) async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'ユーザー凍結',
        message: 'このユーザーを凍結しますか？\n(isBanned: true を設定します)',
        icon: Icons.gavel,
        confirmText: '凍結する',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(context); // Close dialog
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({'isBanned': true});

          if (context.mounted) {
            AppToast.showSuccess(context, 'ユーザーを凍結しました');
          }
        },
      ),
    );
  }

  Future<void> _deleteContent(
      BuildContext context, String collection, String docId) async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'コンテンツ削除',
        message: '$collection/$docId を削除しますか？',
        icon: Icons.delete_forever,
        confirmText: '削除する',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(context); // Close dialog
          await FirebaseFirestore.instance
              .collection(collection)
              .doc(docId)
              .delete();

          if (context.mounted) {
            AppToast.showSuccess(context, 'コンテンツを削除しました');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'open';
    final isResolved = status == 'resolved';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null
        ? DateFormat('yyyy/MM/dd HH:mm').format(createdAt)
        : '不明';

    final targetUserId = data['targetUserId'] ?? data['reportedUserId'];
    final targetBookId = data['targetBookId'] ?? data['bookId'];

    return Card(
      margin: const EdgeInsets.all(8),
      color: isResolved ? Colors.grey.shade200 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '【${data['reason']}】',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
                Text(dateStr, style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Type: ${data['type']}'),
            Text('Description: ${data['description'] ?? "なし"}'),
            const SizedBox(height: 8),
            Text('Target User: ${targetUserId ?? "なし"}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            if (targetBookId != null)
              Text('Book ID: $targetBookId',
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            if (!isResolved)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (targetBookId != null)
                    TextButton(
                      onPressed: () =>
                          _deleteContent(context, 'books', targetBookId),
                      child: const Text('商品削除',
                          style: TextStyle(color: Colors.red)),
                    ),
                  if (targetUserId != null)
                    TextButton(
                      onPressed: () => _banUser(context, targetUserId),
                      child: const Text('ユーザー凍結',
                          style: TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _resolveReport(context),
                    child: const Text('解決済みにする'),
                  ),
                ],
              )
            else
              const Align(
                alignment: Alignment.centerRight,
                child: Text('解決済み',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }
}
