import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String assetPath;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  // ファクトリコンストラクタで簡単にアクセス
  factory LegalDocumentScreen.termsOfService() => const LegalDocumentScreen(
        title: '利用規約',
        assetPath: 'assets/legal/terms_of_service.md',
      );

  factory LegalDocumentScreen.privacyPolicy() => const LegalDocumentScreen(
        title: 'プライバシーポリシー',
        assetPath: 'assets/legal/privacy_policy.md',
      );

  factory LegalDocumentScreen.tokushoho() => const LegalDocumentScreen(
        title: '特定商取引法に基づく表記',
        assetPath: 'assets/legal/tokushoho.md',
      );

  factory LegalDocumentScreen.externalTransmission() =>
      const LegalDocumentScreen(
        title: '外部送信について',
        assetPath: 'assets/legal/external_transmission.md',
      );

  factory LegalDocumentScreen.unofficialService() =>
      const LegalDocumentScreen(
        title: '非公式サービスについて',
        assetPath: 'assets/legal/unofficial_service.md',
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('読み込みに失敗しました: ${snapshot.error}'));
          }
          return Markdown(
            data: snapshot.data ?? '',
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              h1: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 2.0,
              ),
              h2: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 2.0,
              ),
              h3: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.8,
              ),
              p: const TextStyle(
                fontSize: 14,
                height: 1.8,
              ),
              listBullet: const TextStyle(fontSize: 14),
              tableHead: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tableBody: const TextStyle(fontSize: 13),
              tableBorder: TableBorder.all(
                color: Colors.grey.shade300,
                width: 0.5,
              ),
              tableCellsPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              blockSpacing: 12,
            ),
            padding: const EdgeInsets.all(16),
            onTapLink: (text, href, title) async {
              if (href != null) {
                final uri = Uri.parse(href);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
          );
        },
      ),
    );
  }
}
