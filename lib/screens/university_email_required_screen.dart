import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/remote_config_service.dart';
import '../utils/app_toast.dart';

class UniversityEmailRequiredScreen extends StatefulWidget {
  const UniversityEmailRequiredScreen({super.key});

  @override
  State<UniversityEmailRequiredScreen> createState() =>
      _UniversityEmailRequiredScreenState();
}

class _UniversityEmailRequiredScreenState
    extends State<UniversityEmailRequiredScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isSending = false;
  bool _isVerifying = false;
  String? _sentEmail;
  String? _sentUniversityId;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String? _matchedUniversityId(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex == -1 || atIndex == email.length - 1) return null;
    final domain = email.substring(atIndex + 1).toLowerCase();
    final approvedDomains = RemoteConfigService().getApprovedDomains();
    for (final approved in approvedDomains) {
      final normalized = approved.trim().toLowerCase();
      if (normalized.isNotEmpty && domain.endsWith(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    final universityId = _matchedUniversityId(email);
    if (universityId == null) {
      AppToast.showError(context, '登録可能な大学メールアドレスを入力してください。');
      return;
    }

    setState(() => _isSending = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('sendOtp').call({
        'email': email,
        'purpose': 'student',
        'universityId': universityId,
      });
      if (!mounted) return;
      setState(() {
        _sentEmail = email;
        _sentUniversityId = universityId;
      });
      AppToast.showSuccess(context, '認証コードを送信しました。');
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(context, '送信に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      AppToast.showError(context, '6桁の認証コードを入力してください。');
      return;
    }
    final email = _sentEmail;
    final universityId = _sentUniversityId;
    if (email == null || universityId == null) {
      AppToast.showError(context, '先に認証コードを送信してください。');
      return;
    }

    setState(() => _isVerifying = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('verifyOtp').call({
        'email': email,
        'code': code,
        'purpose': 'student',
        'universityId': universityId,
      });
      if (!mounted) return;
      AppToast.showSuccess(context, '大学メール認証が完了しました。');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message ?? '認証に失敗しました。');
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(context, '認証に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentEmail != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('大学メール登録'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mark_email_unread_outlined,
                size: 64, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text(
              '大学メールを登録してください',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '新入生向けの仮利用期間が終了したため、大学メールの認証が完了するまでアプリは利用できません。',
              style: TextStyle(color: Colors.grey.shade700, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              enabled: !sent,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: '大学メールアドレス',
                hintText: 'example@hokudai.ac.jp',
                filled: true,
                fillColor: sent ? Colors.grey.shade200 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!sent)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendOtp,
                  icon: const Icon(Icons.send),
                  label: _isSending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('認証コードを送信'),
                ),
              )
            else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '認証コード',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  icon: const Icon(Icons.check_circle),
                  label: _isVerifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('認証する'),
                ),
              ),
              TextButton(
                onPressed: _isVerifying
                    ? null
                    : () {
                        setState(() {
                          _sentEmail = null;
                          _sentUniversityId = null;
                          _otpController.clear();
                        });
                      },
                child: const Text('メールアドレスを修正する'),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: _signOut,
                child: const Text('ログアウト'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
