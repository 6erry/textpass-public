import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/home/home_header.dart';
import '../widgets/home/next_class_card.dart';
import '../widgets/home/discovery_feed.dart';
import '../widgets/home/category_books_section.dart';
import '../widgets/home/liked_books_section.dart';
import '../utils/legal_notices.dart';
import 'add_book_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback? onSellTap;

  const HomeScreen({super.key, this.onSellTap});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final universityId = userData?['universityId'] as String? ?? '';
        final blockedUserIds =
            List<String>.from(userData?['blockedUserIds'] ?? []);

        if (universityId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('大学情報の登録が必要です')),
          );
        }

        return Scaffold(
          backgroundColor: Colors.grey.shade50, // Light background for contrast
          body: RefreshIndicator(
            onRefresh: () async {
              // Trigger refresh logic if needed (e.g. reload FutureBuilders)
              // For Streams, it's auto-updating, but we might want to refresh 'Future' based widgets like NextClassCard
              // To properly refresh NextClassCard, we might need a GlobalKey or State management (Riverpod).
              // For now, this is a placeholder.
            },
            child: CustomScrollView(
              slivers: [
                const HomeHeader(),

                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        NextClassCard(),
                        SizedBox(height: 16),
                        DiscoveryFeed(),
                      ],
                    ),
                  ),
                ),

                const LikedBooksSection(),

                // Category Sections
                CategoryBooksSection(
                  title: '最新の出品',
                  keywords: const [], // Empty keywords fetches all latest
                  universityId: universityId,
                  blockedUserIds: blockedUserIds,
                ),
                CategoryBooksSection(
                  title: '数学関連',
                  keywords: const ['数学', '微積', '線形代数', '解析', '統計'],
                  universityId: universityId,
                  blockedUserIds: blockedUserIds,
                ),
                CategoryBooksSection(
                  title: '語学',
                  keywords: const [
                    '英語',
                    '中国語',
                    '韓国語',
                    'ドイツ語',
                    'フランス語',
                    'スペイン語',
                    'TOEIC',
                    'TOEFL'
                  ],
                  universityId: universityId,
                  blockedUserIds: blockedUserIds,
                ),
                CategoryBooksSection(
                  title: 'プログラミング',
                  keywords: const [
                    'プログラミング',
                    'アルゴリズム',
                    'Python',
                    'C言語',
                    'Java',
                    '情報'
                  ],
                  universityId: universityId,
                  blockedUserIds: blockedUserIds,
                ),

                // Bottom padding
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
                    child: InformationCard(
                      title: '非公式サービスについて',
                      message: unofficialServiceNotice,
                    ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (onSellTap != null) {
                onSellTap!();
              } else {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddBookScreen()));
              }
            },
            label: const Text('出品'),
            icon: const Icon(Icons.camera_alt),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        );
      },
    );
  }
}
