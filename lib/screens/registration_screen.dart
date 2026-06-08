import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:textpass/utils/app_toast.dart';
import 'freshman_provisional_registration_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _universityEmailController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isRegistering = false;
  bool _isConfigLoading = true;
  String? _configError;
  List<String> _approvedDomains = const [];
  bool _isFreshmanConfigLoading = true;
  bool _freshmanProvisionalEnabled = false;
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _initRemoteConfig();
  }

  Future<void> _initRemoteConfig() async {
    setState(() {
      _isConfigLoading = true;
      _configError = null;
    });

    final remoteConfig = FirebaseRemoteConfig.instance;

    try {
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(minutes: 1),
        ),
      );
      await remoteConfig.fetchAndActivate();

      final raw = remoteConfig.getString('approved_domains');
      final domains = _parseApprovedDomains(raw);
      await _fetchFreshmanRegistrationConfig();

      if (!mounted) return;
      setState(() {
        _approvedDomains = domains;
        _isConfigLoading = false;
        _configError =
            domains.isEmpty ? '現在登録可能なドメインが設定されていません。管理者にお問い合わせください。' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _approvedDomains = const [];
        _isConfigLoading = false;
        _isFreshmanConfigLoading = false;
        _configError = '設定の取得に失敗しました。時間を置いて再度お試しください。';
      });
    }
  }

  Future<void> _fetchFreshmanRegistrationConfig() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('registration')
          .get();
      final data = snapshot.data();
      final enabled = data?['freshmanProvisionalEnabled'] as bool? ?? false;
      final expiresAt = data?['freshmanProvisionalExpiresAt'] as Timestamp?;
      final isNotExpired =
          expiresAt == null || expiresAt.toDate().isAfter(DateTime.now());
      if (!mounted) return;
      setState(() {
        _freshmanProvisionalEnabled = enabled && isNotExpired;
        _isFreshmanConfigLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _freshmanProvisionalEnabled = false;
        _isFreshmanConfigLoading = false;
      });
    }
  }

  List<String> _parseApprovedDomains(String raw) {
    if (raw.isEmpty) return const [];
    try {
      if (raw.trim().startsWith('[')) {
        final decoded = List<dynamic>.from(jsonDecode(raw));
        return decoded
            .whereType<String>()
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Ignore JSON parsing errors and fall back to simple splitting below.
    }

    return raw
        .split(RegExp(r'[;,\\s]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    _universityEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isConfigLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_configError != null && _approvedDomains.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('新規登録')),
        body: Center(child: Text(_configError!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '新規登録',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _universityEmailController,
              decoration: InputDecoration(
                labelText: '大学メールアドレス',
                hintText: 'example@university.ac.jp',
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'パスワード',
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            const Text(
              '登録可能なドメイン',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_approvedDomains.isEmpty) const Text('現在登録可能なドメインは設定されていません。'),
            ..._approvedDomains.map(
              (domain) => Text(
                '- $domain',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _agreedToTerms,
                    onChanged: (value) {
                      setState(() {
                        _agreedToTerms = value ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.grey[800], height: 1.5),
                      children: [
                        TextSpan(
                          text: '利用規約',
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                                'https://tekipa.net/legal/terms_of_service.md'),
                        ),
                        const TextSpan(text: ' と '),
                        TextSpan(
                          text: 'プライバシーポリシー',
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                                'https://tekipa.net/legal/privacy_policy.md'),
                        ),
                        const TextSpan(text: ' に同意します'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (_isRegistering || !_agreedToTerms) ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _agreedToTerms
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isRegistering
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '登録する',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '大学メール未所持の方',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isFreshmanConfigLoading ||
                        !_freshmanProvisionalEnabled ||
                        _isRegistering
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const FreshmanProvisionalRegistrationScreen(),
                          ),
                        );
                      },
                icon: const Icon(Icons.school_outlined),
                label: const Text('1年生（大学メールアドレスを未所持）の方はこちら'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: _freshmanProvisionalEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                  side: BorderSide(
                    color: _freshmanProvisionalEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _freshmanProvisionalEnabled
                  ? '新歓時期など、大学メール配布前の期間だけ利用できます。'
                  : '現在は受付期間外です。',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register() async {
    final universityEmail =
        _universityEmailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (universityEmail.isEmpty || password.isEmpty) {
      _showSnackBar('大学メールアドレスとパスワードを入力してください。');
      return;
    }

    final atIndex = universityEmail.indexOf('@');
    if (atIndex == -1 || atIndex == universityEmail.length - 1) {
      _showSnackBar('有効な大学メールアドレスを入力してください。');
      return;
    }

    final domain = universityEmail.substring(atIndex + 1);
    final matchedDomain = _approvedDomains.firstWhere(
      (parent) => domain.endsWith(parent),
      orElse: () => '',
    );

    if (matchedDomain.isEmpty) {
      _showSnackBar('この大学のメールアドレスは登録できません。');
      return;
    }

    setState(() {
      _isRegistering = true;
    });
    _showLoadingDialog();

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: universityEmail,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'ユーザー情報が取得できませんでした。',
        );
      }

      // await user.sendEmailVerification(); // Logic changed to OTP

      final data = <String, dynamic>{
        'universityEmail': universityEmail,
        'universityId': matchedDomain,
        'isProfileComplete': false,
        'isStudentVerified': false, // Logic changed to OTP
        'favoriteBookIds': <String>[],
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      _closeLoadingDialog();
      // Pop to let AuthGate handle the navigation to VerifyEmailScreen
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      _closeLoadingDialog();
      _showSnackBar(e.message ?? 'ユーザー登録に失敗しました。');
    } catch (_) {
      _closeLoadingDialog();
      _showSnackBar('ユーザー登録に失敗しました。');
    } finally {
      if (mounted) {
        setState(() {
          _isRegistering = false;
        });
      }
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _closeLoadingDialog() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar('リンクを開けませんでした: $urlString');
    }
  }
}
