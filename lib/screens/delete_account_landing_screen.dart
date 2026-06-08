import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/app_custom_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class DeleteAccountLandingScreen extends StatefulWidget {
  const DeleteAccountLandingScreen({super.key});

  @override
  State<DeleteAccountLandingScreen> createState() =>
      _DeleteAccountLandingScreenState();
}

class _DeleteAccountLandingScreenState
    extends State<DeleteAccountLandingScreen> {
  String? _selectedReason;
  final List<String> _reasons = [
    '使い方がわからない',
    '欲しい商品がない',
    '商品が売れない',
    '他のアプリを使うため',
    'その他',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('退会手続き'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.sentiment_dissatisfied_rounded,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              '本当に退会しますか？',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildWarningBox(),
            const SizedBox(height: 32),
            const Text(
              '退会理由（任意）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: _reasons.map((reason) {
                return DropdownMenuItem(
                  value: reason,
                  child: Text(reason),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedReason = value;
                });
              },
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '退会せずに使い続ける',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _showFinalConfirmationDialog(context),
              child: Text(
                'それでも削除する',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          _buildWarningItem('今までの売上履歴がすべて消えます'),
          const SizedBox(height: 12),
          _buildWarningItem('保存したいいね！やサークル情報が復元できません'),
          const SizedBox(height: 12),
          _buildWarningItem('一度削除すると、同じメールアドレスはしばらく使えません'),
        ],
      ),
    );
  }

  Widget _buildWarningItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFinalConfirmationDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '最終確認',
        message: '本当に削除してもよろしいですか？\nこの操作は絶対に取り消せません。',
        confirmText: '削除しない（戻る）', // Primary (Red) -> Cancel Action
        confirmColor: Colors.red,
        cancelText: '削除する', // Secondary (Grey) -> Delete Action
        icon: Icons.warning_rounded,
        onConfirm: () {
          Navigator.pop(context); // Just close dialog
        },
        onCancel: () async {
          // Destructive Action
          Navigator.pop(context); // Close dialog
          try {
            // Show loading
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) =>
                  const Center(child: CircularProgressIndicator()),
            );

            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.delete();
            }

            if (context.mounted) {
              Navigator.pop(context); // Close loading
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } on FirebaseAuthException catch (e) {
            if (context.mounted) {
              Navigator.pop(context); // Close loading
              if (e.code == 'requires-recent-login') {
                showDialog(
                  context: context,
                  builder: (context) => AppCustomDialog(
                    title: '再ログインが必要です',
                    message:
                        'セキュリティのため、アカウント削除には直近のログインが必要です。\n一度ログアウトし、再ログインしてから再度お試しください。',
                    confirmText: 'ログアウトする',
                    confirmColor: Colors.red,
                    cancelText: 'キャンセル',
                    icon: Icons.lock_clock,
                    onConfirm: () async {
                      Navigator.pop(context); // Close dialog
                      await FirebaseAuth.instance.signOut();
                      // AuthGate should handle navigation, but pushing LoginScreen ensures it.
                      // Actually popUntil is safer.
                      if (context.mounted) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      }
                    },
                    onCancel: () => Navigator.pop(context),
                  ),
                );
              } else {
                AppToast.showError(context, '削除に失敗しました: ${e.message}');
              }
            }
          } catch (e) {
            if (context.mounted) {
              Navigator.pop(context); // Close loading
              AppToast.showError(context, '削除に失敗しました: $e');
            }
          }
        },
      ),
    );
  }
}
