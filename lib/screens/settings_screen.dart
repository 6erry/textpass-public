import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/app_custom_dialog.dart';
import '../widgets/app_custom_input_dialog.dart';
import 'delete_account_screen.dart';
import 'eula_screen.dart';
import 'blocked_users_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('エラー')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          final userData = snapshot.data?.data();
          // Assuming 'email' in Firestore is the University Email (or stored separately)
          // If not present, fallback to Auth email.
          // User requested "University Email" and "Contact Email".
          // Let's assume 'universityEmail' field exists or we treat the initial Auth email as such?
          // For now, I'll use 'universityEmail' field if exists, else 'email' field, else Auth email.
          final universityEmail = userData?['universityEmail'] as String? ??
              userData?['email'] as String? ??
              user.email;
          final contactEmail = userData?['contactEmail'] as String? ??
              user.email; // Default to Auth email if not set

          return ListView(
            children: [
              _buildSectionHeader('アカウント'),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('大学メールアドレス'),
                subtitle: Text(universityEmail ?? '未設定'),
                // Read-only
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('連絡用メールアドレス'),
                subtitle: Text(contactEmail ?? '未設定'),
                onTap: () =>
                    _showEmailEditDialog(context, user.uid, contactEmail),
              ),
              ListTile(
                leading: Icon(
                  Icons.lock_outline,
                  color: user.providerData
                          .any((info) => info.providerId == 'password')
                      ? null
                      : Colors.grey,
                ),
                title: Text(
                  'パスワード変更',
                  style: TextStyle(
                    color: user.providerData
                            .any((info) => info.providerId == 'password')
                        ? null
                        : Colors.grey,
                  ),
                ),
                subtitle: user.providerData
                        .any((info) => info.providerId == 'password')
                    ? Text('送付先: ${user.email ?? "不明"}')
                    : const Text('Google/Appleログインのため設定不要'),
                onTap: user.providerData
                        .any((info) => info.providerId == 'password')
                    ? () => _showPasswordResetDialog(context, user.email)
                    : () {
                        AppToast.show(context,
                            'このアカウントはソーシャルログインを使用しているため、パスワードの変更は不要です。');
                      },
              ),
              _buildSectionHeader('プライバシー・セキュリティ'),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('ブロックしたユーザー'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BlockedUsersScreen()),
                  );
                },
              ),
              _buildSectionHeader('アプリについて'),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('利用規約'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const EulaScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('バージョン'),
                trailing: Text(_version),
              ),
              _buildSectionHeader('その他'),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('ログアウト', style: TextStyle(color: Colors.red)),
                onTap: () => _showLogoutDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title:
                    const Text('アカウント削除', style: TextStyle(color: Colors.red)),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Future<void> _showEmailEditDialog(
      BuildContext context, String uid, String? currentEmail) async {
    final controller = TextEditingController(text: currentEmail);

    await showDialog(
      context: context,
      builder: (context) => AppCustomInputDialog(
        title: '連絡用メールアドレス変更',
        icon: Icons.email_outlined,
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '新しいメールアドレス',
            helperText: 'パスワードリセット等の通知はこのアドレスに送信されます。',
            helperMaxLines: 2,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newEmail = controller.text.trim();
              if (newEmail.isNotEmpty) {
                try {
                  // Update Firestore
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .set(
                    {
                      'contactEmail': newEmail,
                      'isContactEmailVerified': false, // Flag as unverified
                    },
                    SetOptions(merge: true),
                  );

                  // Note: detailed auth update removed in favor of OTP verification flow via Todo List.
                  if (context.mounted) {
                    AppToast.show(context, '保存しました。やることリストから認証を完了してください。');
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppToast.show(context, 'エラー: $e');
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPasswordResetDialog(
      BuildContext context, String? email) async {
    if (email == null) {
      AppToast.show(context, '有効なメールアドレスが登録されていません。');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'パスワード変更',
        message: 'ログイン用メールアドレス（$email）宛にパスワード再設定の案内を送信します。\nよろしいですか？',
        icon: Icons.lock_reset,
        confirmText: '送信',
        onConfirm: () async {
          Navigator.pop(context); // Close dialog
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
            if (context.mounted) {
              AppToast.show(context, '再設定メールを送信しました。受信トレイをご確認ください。');
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

  Future<void> _showLogoutDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: 'ログアウト',
        message: '本当にログアウトしますか？\nログイン画面に戻ります。',
        confirmText: 'ログアウト',
        confirmColor: Colors.red,
        icon: Icons.logout_rounded,
        onConfirm: () async {
          Navigator.pop(context); // Close dialog first
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            Navigator.of(context)
                .popUntil((route) => route.isFirst); // Go to login/auth gate
          }
        },
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const DeleteAccountLandingScreen()),
    );
  }
}
