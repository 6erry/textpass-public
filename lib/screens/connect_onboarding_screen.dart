import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/stripe_service.dart';
import 'package:textpass/utils/app_toast.dart';

class ConnectOnboardingScreen extends StatefulWidget {
  const ConnectOnboardingScreen({super.key});

  @override
  State<ConnectOnboardingScreen> createState() =>
      _ConnectOnboardingScreenState();
}

class _ConnectOnboardingScreenState extends State<ConnectOnboardingScreen> {
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _startOnboarding() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Stripeアカウントを準備中';
    });

    try {
      final stripeService = StripeService();

      // 1. Create Account
      final accountId = await stripeService.createConnectAccount();

      // 2. Create Link
      final url = await stripeService.createAccountLink(accountId);

      // 3. Launch URL
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          setState(() {
            _statusMessage = 'ブラウザで設定を完了してください。\n完了したら「確認する」を押してください。';
          });
        }
      } else {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'エラーが発生しました: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // In a real app, we would check the account status via an API call.
      // For now, we just check if we have the account ID in Firestore,
      // assuming the user completed the flow if they clicked "Check".
      // Ideally, we should have a webhook or a function to check `details_submitted`.

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final stripeAccountId =
          data?['stripeAccountId'] ?? data?['stripeConnectedAccountId'];

      if (!mounted) return;

      if (stripeAccountId != null) {
        AppToast.show(context, '連携情報を確認しました（簡易チェック）');
        Navigator.of(context).pop();
      } else {
        AppToast.show(context, '連携情報が見つかりません。もう一度お試しください。');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラー: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('売上受け取り設定')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_balance, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                '売上を受け取るには\nStripeアカウントの連携が必要です',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '本人確認書類と銀行口座情報をご用意ください。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey.shade100,
                  child: Text(_statusMessage!, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 24),
              if (_statusMessage == null)
                ElevatedButton(
                  onPressed: _isLoading ? null : _startOnboarding,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('連携を開始/更新する'),
                )
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _isLoading ? null : _checkStatus,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('完了を確認する'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading ? null : _startOnboarding,
                      child: const Text('連携をやり直す'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
