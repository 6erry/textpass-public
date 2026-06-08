import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:textpass/utils/app_toast.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isSending = false;
  bool _isVerifying = false;
  // bool _isOtpSent = false; // NOTE: Linter says unused. We use it for UI state if needed, but currently simplistic.
  // Actually we keep it to be safe if logic changes, or remove if strict.
  // Let's keep it consistent with previous logic, but suppressing lint if needed or just using it.
  // In previous logic it was used to toggle UI in ProfileSetup, but here?
  // Here we just stay on this screen.

  Timer? _timer; // Helper timer if needed for resend cooldown (optional)

  @override
  void initState() {
    super.initState();
    // Automatically send OTP on first load
    _sendOtp();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final email = user.email!;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final universityId = userDoc.data()?['universityId'] as String?;

    setState(() {
      _isSending = true;
    });

    try {
      await FirebaseFunctions.instance.httpsCallable('sendOtp').call({
        'email': email,
        'purpose': 'student',
        'universityId': universityId,
      });

      if (!mounted) return;
      setState(() {
        _isSending = false;
        // _isOtpSent = true;
      });
      AppToast.show(context, '認証コードを送信しました');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      AppToast.showError(context, '送信エラー: $e');
    }
  }

  Future<void> _verifyOtp() async {
    final inputCode = _otpController.text.trim();
    if (inputCode.length != 6) {
      AppToast.showError(context, '6桁のコードを入力してください');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final universityId = userDoc.data()?['universityId'] as String?;
      await FirebaseFunctions.instance.httpsCallable('verifyOtp').call({
        'email': user.email!,
        'code': inputCode,
        'purpose': 'student',
        'universityId': universityId,
      });

      if (mounted) {
        AppToast.showSuccess(context, '認証に成功しました！');
        // AuthGate will detect the change in 'isStudentVerified' and redirect
      }
    } catch (e) {
      if (mounted) {
        var msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        AppToast.showError(context, msg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '不明なメールアドレス';

    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 22,
        color: Color.fromRGBO(30, 60, 87, 1),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(16),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: const Color.fromRGBO(234, 239, 243, 1),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('メール認証')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.mark_email_unread_outlined,
                size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              '認証コードを入力',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '$email 宛に\n6桁の認証コードを送信しました。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Pinput(
              controller: _otpController,
              length: 6,
              defaultPinTheme: defaultPinTheme,
              focusedPinTheme: focusedPinTheme,
              submittedPinTheme: submittedPinTheme,
              pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
              showCursor: true,
              onCompleted: (pin) => _verifyOtp(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '認証する',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isSending ? null : _sendOtp,
              child: _isSending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('認証コードを再送信'),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('アカウントを切り替える (ログアウト)'),
            ),
          ],
        ),
      ),
    );
  }
}
