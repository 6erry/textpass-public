import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main_screen.dart';

class TermsConsentScreen extends StatefulWidget {
  const TermsConsentScreen({super.key, required this.user});

  final User user;

  @override
  State<TermsConsentScreen> createState() => _TermsConsentScreenState();
}

class _TermsConsentScreenState extends State<TermsConsentScreen> {
  static const String _tosVersion = '2024-11-21';

  bool _agreed = false;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _acceptTerms() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set(
        {
          'tosAccepted': true,
          'tosAcceptedAt': FieldValue.serverTimestamp(),
          'tosVersion': _tosVersion,
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = '同意の保存に失敗しました: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('利用規約・プライバシー'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TextPass 利用規約（抜粋）',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '・学生向け教科書の売買・譲渡に限定したマーケットプレイスです。\n'
                          '・禁止行為：著作権侵害物の販売、なりすまし、スパム、違法行為。\n'
                          '・本人確認用途として学内メールでの認証を行います。\n'
                          '・トラブル時は通報・ブロック機能を利用し、運営が調査・対応します。\n'
                          '・退会時はFirebase Auth/Firestore上の個人データを削除します。\n'
                          '・決済はStripeを利用し、利用料・販売手数料のルールに従います。\n'
                          '\n'
                          'プライバシーポリシー（抜粋）\n'
                          '・取引・チャット内容は運営が不正検知のために確認する場合があります。\n'
                          '・ログ（アクセス・決済エラー等）を運用改善のために保存します。\n'
                          '・詳細な規約・ポリシーはアプリ内のヘルプリンクから随時更新します。',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: _isSubmitting
                        ? null
                        : (v) {
                            setState(() {
                              _agreed = v ?? false;
                            });
                          },
                  ),
                  const Expanded(
                    child: Text(
                      '利用規約・プライバシーポリシーに同意します',
                      style: TextStyle(fontSize: 14),
                    ),
                  )
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_agreed || _isSubmitting ? null : _acceptTerms,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('同意して進む'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'バージョン: $_tosVersion',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
