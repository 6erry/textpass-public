import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:textpass/utils/app_toast.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isReloading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('メール認証')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '確認メールを送信しました。メール内のリンクをクリックしてください。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isReloading ? null : _reloadUser,
                child: _isReloading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('認証状態を再確認'),
              ),
              TextButton(
                onPressed: _goBackToLogin,
                child: const Text('ログイン画面に戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reloadUser() async {
    setState(() => _isReloading = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) return;
      AppToast.show(context, '最新の認証状態を取得しました。');
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '認証状態の取得に失敗しました。');
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  Future<void> _goBackToLogin() async {
    await FirebaseAuth.instance.signOut();
    // AuthGate will handle the navigation to LoginScreen
  }
}
