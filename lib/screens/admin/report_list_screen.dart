import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_custom_dialog.dart';
import '../../models/book.dart';
import '../../models/event.dart';
import '../book_detail_screen.dart';
import '../event/event_detail_screen.dart';
import '../circle/circle_detail_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class ReportListScreen extends StatelessWidget {
  const ReportListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adminService = AdminService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('通報一覧'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: adminService.getUnresolvedReportsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('通報はありません'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final reportId = docs[index].id;
              final reason = data['reason'] ?? '不明な理由';
              final description = data['detail'] ?? data['description'] ?? '';
              final type = data['targetType'] ?? data['type'] ?? 'unknown';
              final status = data['status'] ?? 'pending';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              final isResolved = status == 'resolved';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ExpansionTile(
                  leading: Icon(
                    isResolved ? Icons.check_circle : Icons.report_problem,
                    color: isResolved ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    reason,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration:
                          isResolved ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text(
                    '${DateFormat('yyyy/MM/dd HH:mm').format(createdAt ?? DateTime.now())} - $type',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (description.isNotEmpty) ...[
                            const Text('詳細:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(description),
                            const SizedBox(height: 16),
                          ],
                          const Text('対象ID:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              'Target: ${data['targetId'] ?? data['targetBookId'] ?? data['bookId'] ?? data['targetEventId'] ?? data['targetCircleId'] ?? 'N/A'}'),
                          Text(
                              'User: ${data['targetUserId'] ?? data['reportedUserId'] ?? 'N/A'}'),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _navigateToTarget(context, data),
                                child: const Text('対象を確認'),
                              ),
                              if (!isResolved) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _showActionDialog(
                                      context, adminService, reportId, data),
                                  child: const Text('対応する'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _navigateToTarget(
      BuildContext context, Map<String, dynamic> data) async {
    final type = data['type'];
    final targetType = data['targetType'] ?? type;
    final String? targetId = targetType == 'book' || type == 'listing'
        ? (data['targetBookId'] ?? data['bookId'])
        : targetType == 'event'
            ? (data['targetEventId'] ?? data['targetId'])
            : targetType == 'circle'
                ? (data['targetCircleId'] ?? data['targetId'])
                : null;

    if (targetId == null) {
      AppToast.show(context, '対象IDが見つかりません');
      return;
    }

    if (targetType == 'book' || type == 'listing') {
      // Navigate to BookDetail
      // We need to fetch the book first or let BookDetail handle it?
      // BookDetail usually takes a Book object.
      // Let's fetch it here for simplicity.
      try {
        final doc = await FirebaseFirestore.instance
            .collection('books')
            .doc(targetId)
            .get();
        if (doc.exists && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookDetailScreen(book: Book.fromFirestore(doc)),
            ),
          );
        } else if (context.mounted) {
          AppToast.show(context, '対象の投稿が見つかりません (削除済みの可能性があります)');
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, 'エラー: $e');
        }
      }
    } else if (targetType == 'event') {
      // Navigate to EventDetail
      try {
        final doc = await FirebaseFirestore.instance
            .collection('events')
            .doc(targetId)
            .get();
        if (doc.exists && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  EventDetailScreen(event: Event.fromFirestore(doc)),
            ),
          );
        } else if (context.mounted) {
          AppToast.show(context, '対象のイベントが見つかりません (削除済みの可能性があります)');
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, 'エラー: $e');
        }
      }
    } else if (targetType == 'circle') {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CircleDetailScreen(circleId: targetId),
          ),
        );
      }
    }
  }

  void _showActionDialog(BuildContext context, AdminService service,
      String reportId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('対応を選択'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmDelete(context, service, data);
            },
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('コンテンツを非表示にする', style: TextStyle(color: Colors.red)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmBan(context, service,
                  data['targetUserId'] ?? data['reportedUserId']);
            },
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('ユーザーをBANする', style: TextStyle(color: Colors.red)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await service.resolveReport(reportId);
              if (context.mounted) {
                AppToast.show(context, '解決済みにしました');
              }
            },
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('問題なしとして解決'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AdminService service,
      Map<String, dynamic> data) async {
    final type = data['type'];
    final targetType = data['targetType'] ?? type;
    final docId = targetType == 'book' || type == 'listing'
        ? (data['targetBookId'] ?? data['bookId'])
        : (targetType == 'event'
            ? (data['targetEventId'] ?? data['targetId'])
            : (targetType == 'circle'
                ? (data['targetCircleId'] ?? data['targetId'])
                : null));
    final collection = targetType == 'book' || type == 'listing'
        ? 'books'
        : (targetType == 'event'
            ? 'events'
            : (targetType == 'circle' ? 'circles' : null));

    if (docId == null || collection == null) {
      AppToast.show(context, '削除対象が特定できません');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'コンテンツ非表示',
        message: '本当にこのコンテンツを非表示にしますか？',
        icon: Icons.delete_forever,
        confirmText: '削除',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(context);
          try {
            await service.moderateContent(
              collection: collection,
              docId: docId,
              status: 'hidden',
              reason: data['reason']?.toString(),
            );
            if (context.mounted) {
              AppToast.show(context, '非表示にしました');
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(context, 'エラー: $e');
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmBan(
      BuildContext context, AdminService service, String? uid) async {
    if (uid == null) return;

    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'ユーザーBAN',
        message: '本当にこのユーザーをBANしますか？\nユーザーはログインできなくなります。',
        icon: Icons.block,
        confirmText: 'BAN実行',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(context);
          try {
            await service.banUser(uid);
            if (context.mounted) {
              AppToast.show(context, 'ユーザーをBANしました');
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(context, 'エラー: $e');
            }
          }
        },
      ),
    );
  }
}
