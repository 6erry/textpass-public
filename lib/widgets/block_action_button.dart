import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/report_service.dart';
import 'app_custom_dialog.dart';
import 'app_custom_input_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class BlockActionButton extends StatefulWidget {
  const BlockActionButton({
    super.key,
    required this.targetUserId,
    this.transactionId,
  });

  final String targetUserId;
  final String? transactionId;

  @override
  State<BlockActionButton> createState() => _BlockActionButtonState();
}

class _BlockActionButtonState extends State<BlockActionButton> {
  String get targetUserId => widget.targetUserId;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        if (value == 'block') {
          _confirmBlock(context, user.uid);
        } else if (value == 'report') {
          _showReportDialog(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'block',
          child: Text('このユーザーをブロックする', style: TextStyle(color: Colors.red)),
        ),
        const PopupMenuItem(
          value: 'report',
          child: Text('通報する'),
        ),
      ],
    );
  }

  Future<void> _showCannotBlockDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'ブロックできません',
        message: '取引中のユーザーはブロックできません。\n取引が完了またはキャンセルされた後に再度お試しください。',
        icon: Icons.error_outline,
        confirmText: 'OK',
        showCancelButton: false,
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _confirmBlock(BuildContext context, String currentUid) async {
    // 1. 取引中チェック
    final hasActive = await UserService().hasActiveTransaction(targetUserId);
    if (hasActive) {
      if (!context.mounted) return;
      _showCannotBlockDialog(context);
      return;
    }

    // 2. ブロック確認
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'ブロックしますか？',
        message: 'このユーザーとのやり取りができなくなります。',
        icon: Icons.block,
        confirmText: 'ブロック',
        confirmColor: Colors.red,
        onConfirm: () async {
          Navigator.pop(context); // Close dialog
          // 3. 実行
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUid)
                .set(
              {
                'blockedUserIds': FieldValue.arrayUnion([targetUserId]),
              },
              SetOptions(merge: true),
            );
            if (context.mounted) {
              AppToast.show(context, 'ブロックしました');
              Navigator.of(context)
                  .pop(); // Go back to previous screen (likely profile)
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(context, 'エラーが発生しました');
            }
          }
        },
      ),
    );
  }

  Future<void> _showReportDialog(BuildContext context) async {
    final reasons = [
      'Spam (スパム)',
      'Inappropriate Content (不適切なコンテンツ)',
      'Harassment (迷惑行為)',
      'Other (その他)',
    ];

    final descriptionController = TextEditingController();
    String? selectedReason;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AppCustomInputDialog(
            title: '通報',
            icon: Icons.report_problem_outlined,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('通報の理由',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: reasons.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedReason = value);
                  },
                  hint: const Text('理由を選択してください'),
                ),
                const SizedBox(height: 16),
                const Text('詳細（任意）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    hintText: '詳細を入力してください',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () async {
                        Navigator.pop(context); // Close dialog
                        final description = descriptionController.text;
                        try {
                          await ReportService().submitReport(
                            type: 'user',
                            reason: selectedReason!,
                            targetUserId: targetUserId,
                            description: description,
                            transactionId: widget.transactionId,
                          );

                          if (!context.mounted) return;
                          AppToast.show(context, '通報を受け付けました。');
                        } catch (e) {
                          if (!context.mounted) return;
                          AppToast.show(context, 'エラーが発生しました: $e');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('送信'),
              ),
            ],
          );
        },
      ),
    );
  }
}
