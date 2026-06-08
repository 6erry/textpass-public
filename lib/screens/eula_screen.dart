import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/auth_gate.dart';
import '../widgets/app_custom_dialog.dart';
import '../utils/legal_notices.dart';
import 'legal/legal_document_screen.dart';

class EulaScreen extends StatefulWidget {
  const EulaScreen({super.key});

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  bool _isLoading = false;
  bool _agreed = false;

  Future<void> _agreeToEula() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_agreed_eula', true);

    if (!mounted) return;

    // Navigate to AuthGate which handles the auth flow
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  void _declineEula() {
    // In a real app, you might close the app or show a dialog saying it's required.
    // For now, we'll show a dialog.
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '同意が必要です',
        message: '本アプリを利用するには、利用規約とプライバシーポリシーへの同意が必要です。',
        icon: Icons.warning_amber_rounded,
        confirmText: '閉じる',
        showCancelButton: false,
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('法的情報への同意')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'エンドユーザー使用許諾契約 (EULA)',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '本アプリ（TextPass）をご利用いただくには、以下の利用規約およびプライバシーポリシーにご同意いただく必要があります。\n各リンクから内容をご確認ください。',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    const InformationCard(
                      title: '非公式サービスについて',
                      message: unofficialServiceNotice,
                    ),
                    const SizedBox(height: 32),
                    // 利用規約リンク
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('利用規約を読む'),
                        trailing: const Icon(Icons.chevron_right),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LegalDocumentScreen.termsOfService(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // プライバシーポリシーリンク
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('プライバシーポリシーを読む'),
                        trailing: const Icon(Icons.chevron_right),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LegalDocumentScreen.privacyPolicy(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 同意チェックボックス
                  CheckboxListTile(
                    value: _agreed,
                    onChanged: (val) => setState(() => _agreed = val ?? false),
                    title: const Text(
                      '利用規約およびプライバシーポリシーに同意します',
                      style: TextStyle(fontSize: 14),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_agreed && !_isLoading) ? _agreeToEula : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('同意して利用を開始する'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _declineEula,
                    child: const Text('同意しない',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
