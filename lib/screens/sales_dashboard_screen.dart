import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:intl/intl.dart';
import '../services/stripe_service.dart';
import '../utils/legal_notices.dart';
import '../widgets/app_custom_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class SalesDashboardScreen extends StatefulWidget {
  const SalesDashboardScreen({super.key});

  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isOnboarded = false;
  Map<String, dynamic>? _balanceData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboardingStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOnboardingStatus();
    }
  }

  Future<void> _checkOnboardingStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Check if user has an account ID (Local Check)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final hasAccountId = data?['stripeAccountId'] != null ||
          data?['stripeConnectedAccountId'] != null;
      final isFlagTrue = data?['isStripeOnboarded'] == true;

      if (isFlagTrue) {
        _isOnboarded = true;
        await _fetchBalance();
      } else if (hasAccountId) {
        // 2. If ID exists but flag is false, try fetching balance acts as check
        try {
          await _fetchBalance(); // This throws if account is restricted/incomplete?
          // If we got here, we assume valid enough to show dashboard
          // Note: _fetchBalance sets _balanceData inside setState
          _isOnboarded = true;
        } catch (e) {
          // If balance fetch failed, likely incomplete account
          _isOnboarded = false;
        }
      } else {
        _isOnboarded = false;
      }
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchBalance() async {
    try {
      final balance = await StripeService().getAccountBalance();
      setState(() {
        _balanceData = balance;
      });
    } catch (e) {
      debugPrint('Error fetching balance: $e');
    }
  }

  Future<void> _startOnboarding() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Create Connect Account
      final accountId = await StripeService().createConnectAccount();

      // 2. Create Account Link
      final url = await StripeService().createAccountLink(accountId);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('ブラウザを開けませんでした');
      }

      if (mounted) {
        AppToast.show(context, 'ブラウザでStripeの設定を行ってください');

        // Show a dialog to confirm completion (Manual trigger)
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AppCustomDialog(
            title: '設定の確認',
            message: 'ブラウザでの設定は完了しましたか？',
            icon: Icons.settings,
            confirmText: '完了した',
            onConfirm: () {
              Navigator.pop(context);
              _checkOnboardingStatus();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openStripeDashboard() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final url = await StripeService().createStripeLoginLink();
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('ブラウザを開けませんでした');
      }
      if (mounted) {
        AppToast.show(context, 'ブラウザでダッシュボードを開きます');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'エラーが発生しました: $e');
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
      appBar: AppBar(
        title: const Text('売上・振込申請'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isOnboarded
              ? _buildDashboard()
              : _buildOnboardingPrompt(),
    );
  }

  Widget _buildOnboardingPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet,
              size: 80, color: Colors.grey),
          const SizedBox(height: 24),
          const Text(
            '売上を受け取るには\n本人確認が必要です',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            '安心・安全な取引のために、Stripe連携による本人確認をお願いしています。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const InformationCard(
            title: '売上管理について',
            message: stripeConnectBalanceNotice,
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '本人確認を始める',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    int available = 0;
    int pending = 0;

    if (_balanceData != null) {
      // Safe parsing
      try {
        final availRaw = _balanceData!['available'];
        if (availRaw is int) {
          available = availRaw;
        } else if (availRaw is List && availRaw.isNotEmpty) {
          available = (availRaw[0]['amount'] as num?)?.toInt() ?? 0;
        } else if (availRaw is Map) {
          available = (availRaw['amount'] as num?)?.toInt() ?? 0;
        }

        final pendingRaw = _balanceData!['pending'];
        if (pendingRaw is int) {
          pending = pendingRaw;
        } else if (pendingRaw is List && pendingRaw.isNotEmpty) {
          pending = (pendingRaw[0]['amount'] as num?)?.toInt() ?? 0;
        } else if (pendingRaw is Map) {
          pending = (pendingRaw['amount'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint('Balance parsing error: $e');
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBalanceCard('利用可能な残高', available),
          const SizedBox(height: 16),
          _buildBalanceCard('振込申請中の残高', pending, isPending: true),
          const SizedBox(height: 16),
          const InformationCard(
            title: '売上管理について',
            message: stripeConnectBalanceNotice,
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 32),
          const Text(
            'メニュー',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Stripeダッシュボードを開く'),
            subtitle: const Text('詳細な取引履歴や口座情報の確認・変更'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openStripeDashboard,
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(String title, int amount, {bool isPending = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPending ? Colors.grey.shade100 : Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPending
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isPending ? Colors.grey.shade600 : Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            NumberFormat.currency(locale: 'ja_JP', symbol: '¥').format(amount),
            style: TextStyle(
              color: isPending ? Colors.black : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
