import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/app_toast.dart';

class ContactEmailVerificationDialog extends StatefulWidget {
  final String contactEmail;

  const ContactEmailVerificationDialog({
    super.key,
    required this.contactEmail,
  });

  @override
  State<ContactEmailVerificationDialog> createState() =>
      _ContactEmailVerificationDialogState();
}

class _ContactEmailVerificationDialogState
    extends State<ContactEmailVerificationDialog> {
  final _otpController = TextEditingController();
  bool _isSaving = false;
  bool _isOtpSent = false;
  String? _sentOtpEmail;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFunctions.instance.httpsCallable('sendOtp').call({
        'email': widget.contactEmail,
        'purpose': 'contact',
      });

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isOtpSent = true;
        _sentOtpEmail = widget.contactEmail;
      });
      AppToast.show(context, '認証メールを送信しました。コードを入力してください。');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    }
  }

  Future<void> _verifyOtp() async {
    final inputCode = _otpController.text.trim();
    if (inputCode.length != 6) {
      AppToast.show(context, '6桁のコードを入力してください。');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (widget.contactEmail != _sentOtpEmail) {
        throw Exception('メールアドレスが一致しません。最初からやり直してください。');
      }

      await FirebaseFunctions.instance.httpsCallable('verifyOtp').call({
        'email': widget.contactEmail,
        'code': inputCode,
        'purpose': 'contact',
      });

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        AppToast.show(context, '連絡用メールアドレスの認証が完了しました！');
        Navigator.pop(context); // Close dialog
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        var msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        AppToast.show(context, msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '連絡用メールアドレス認証',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '送り先: ${widget.contactEmail}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            if (!_isOtpSent) ...[
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _sendOtp,
                icon: const Icon(Icons.send),
                label: const Text('認証コードを送信'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '※認証コードが記載されたメールが送信されます。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(color: Colors.grey.shade300),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Theme.of(context).primaryColor, width: 2),
                  ),
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _verifyOtp,
                icon: const Icon(Icons.check_circle),
                label: const Text('認証する'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _isOtpSent = false;
                        });
                      },
                child: const Text('再送信 / アドレス確認'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
