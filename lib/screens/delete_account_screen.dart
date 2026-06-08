import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アカウント削除')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'アカウントを削除すると、以下のデータがすべて削除されます。この操作は取り消せません。',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('・プロフィール情報'),
            const Text('・出品した教科書'),
            const Text('・チャット履歴'),
            const Text('・時間割データ'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('キャンセル（アカウントを残す）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _isLoading ? null : _confirmDelete,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('アカウントを削除する'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '最終確認',
        message: '本当にアカウントを削除しますか？\nこの操作は元に戻せません。',
        icon: Icons.warning_amber_rounded,
        // Swap actions: Confirm (Red) = Cancel, Cancel (Text) = Delete
        confirmText: 'キャンセル',
        confirmColor: Colors.red,
        onConfirm: () {
          Navigator.pop(context);
        },
        cancelText: '削除する',
        onCancel: () async {
          Navigator.pop(context); // Close dialog
          await _deleteAccount();
        },
      ),
    );
  }

  Future<void> _deleteAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Firestore data deletion logic would go here (or handled by Cloud Functions)
      // For now, just delete the Auth user
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'アカウント削除に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
