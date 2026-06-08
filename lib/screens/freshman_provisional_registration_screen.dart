import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_toast.dart';
import '../widgets/auth_gate.dart';

class FreshmanProvisionalRegistrationScreen extends StatefulWidget {
  const FreshmanProvisionalRegistrationScreen({super.key});

  @override
  State<FreshmanProvisionalRegistrationScreen> createState() =>
      _FreshmanProvisionalRegistrationScreenState();
}

class _FreshmanProvisionalRegistrationScreenState
    extends State<FreshmanProvisionalRegistrationScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agreedToTerms = false;
  bool _isRegistering = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      AppToast.showError(context, 'メールアドレスとパスワードを入力してください。');
      return;
    }
    if (!_agreedToTerms) {
      AppToast.showError(context, '利用規約とプライバシーポリシーに同意してください。');
      return;
    }

    setState(() => _isRegistering = true);

    User? createdUser;
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      createdUser = credential.user;
      if (createdUser == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'ユーザー情報を取得できませんでした。',
        );
      }

      await FirebaseFunctions.instance
          .httpsCallable('createFreshmanProvisionalUser')
          .call();

      if (!mounted) return;
      AppToast.showSuccess(context, '新入生向けの仮登録が完了しました。');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message ?? '仮登録に失敗しました。');
    } on FirebaseFunctionsException catch (e) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {
          await FirebaseAuth.instance.signOut();
        }
      }
      if (!mounted) return;
      final message = e.code == 'failed-precondition'
          ? '現在、新入生向けの仮登録は受け付けていません。'
          : e.message ?? '仮登録に失敗しました。';
      AppToast.showError(context, message);
    } catch (_) {
      if (!mounted) return;
      AppToast.showError(context, '仮登録に失敗しました。');
    } finally {
      if (mounted) {
        setState(() => _isRegistering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新入生向け仮登録')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '大学メールアドレスを受け取る前の1年生向けです。',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '新歓情報、時間割、教科書情報などを確認できます。レビュー閲覧や投稿など一部機能は、大学メール認証後に利用できます。',
              style: TextStyle(color: Colors.grey.shade700, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: '連絡用メールアドレス',
                hintText: 'example@gmail.com',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'パスワード',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreedToTerms,
              onChanged: (value) {
                setState(() => _agreedToTerms = value ?? false);
              },
              title: const Text('利用規約とプライバシーポリシーに同意します'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isRegistering || !_agreedToTerms ? null : _register,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isRegistering
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('仮登録する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
