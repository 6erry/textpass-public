import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/stripe_service.dart';
import 'chat_list_screen.dart';
import 'favorites_screen.dart';
import 'my_listings_screen.dart';
import 'purchased_items_screen.dart';
import 'sales_dashboard_screen.dart';
import 'user_profile_screen.dart';
import 'legal/legal_document_screen.dart';
import 'circle/circle_onboarding_screen.dart';
import '../services/notification_service.dart';
import 'notification_screen.dart';
import 'settings_screen.dart';
import 'keyword_alert_screen.dart';
import 'bundle_requests_screen.dart';
import '../services/user_service.dart';
import 'admin/admin_dashboard_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'マイページ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          StreamBuilder<int>(
            stream: NotificationService().getUnreadCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: Colors.black),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const NotificationScreen()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey.shade200,
                    child:
                        const Icon(Icons.person, size: 36, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'ユーザー',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      if (user == null) {
                        AppToast.show(context, 'ログインが必要です');
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserProfileScreen(userId: user.uid),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: const Text(
                      'プロフィール',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Selling Section
            _buildSectionHeader('出品・購入'),
            _buildMenuItem(
              context,
              icon: Icons.store_mall_directory_outlined,
              title: '出品した商品',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const MyListingsScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.shopping_bag_outlined,
              title: '購入した商品',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const PurchasedItemsScreen()),
                );
              },
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.favorite_border,
              title: 'お気に入り一覧',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FavoritesScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.chat_bubble_outline,
              title: '取引メッセージ',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatListScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.library_books_outlined,
              title: 'まとめ買い依頼',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BundleRequestsScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.notifications_active_outlined,
              title: 'キーワード通知設定',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KeywordAlertScreen(),
                  ),
                );
              },
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.groups_outlined,
              title: 'サークル管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CircleOnboardingScreen()),
              ),
            ),
            const SizedBox(height: 12),

            // Settings Section
            _buildSectionHeader('設定・その他'),
            _buildBalanceCard(theme),
            const SizedBox(height: 12),
            _buildMenuItem(
              context,
              icon: Icons.currency_yen,
              title: '売上管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SalesDashboardScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.settings_outlined,
              title: '設定',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.description_outlined,
              title: '利用規約',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.termsOfService(),
                ),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.privacy_tip_outlined,
              title: 'プライバシーポリシー',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.privacyPolicy(),
                ),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.store_outlined,
              title: '特定商取引法に基づく表記',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.tokushoho(),
                ),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.send_outlined,
              title: '外部送信について',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.externalTransmission(),
                ),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.info_outline,
              title: '非公式サービスについて',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.unofficialService(),
                ),
              ),
            ),
            _buildDivider(),
            _buildMenuItem(
              context,
              icon: Icons.help_outline,
              title: 'ヘルプ・お問い合わせ',
              onTap: () {
                // TODO: Implement Help Screen
              },
            ),
            const SizedBox(height: 32),

            // Admin Section
            FutureBuilder<bool>(
              future: UserService().isAdmin(),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Column(
                    children: [
                      _buildSectionHeader('管理者メニュー'),
                      _buildMenuItem(
                        context,
                        icon: Icons.admin_panel_settings,
                        title: '管理者ダッシュボード',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const AdminDashboardScreen()),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.black87),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 0.5, indent: 56);
  }

  Widget _buildBalanceCard(ThemeData theme) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        // Use the same logic: if ID exists, we hide the "Prepare" banner
        final hasAccountId = data?['stripeAccountId'] != null ||
            data?['stripeConnectedAccountId'] != null;
        final isFlagTrue = data?['isStripeOnboarded'] == true;

        final isOnboarded = hasAccountId || isFlagTrue;

        if (!isOnboarded) {
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const SalesDashboardScreen()),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: Colors.white, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '売上を受け取る準備',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Stripe Connectで入金を管理します >',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: StripeService().getAccountBalance(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ));
            }
            if (snapshot.hasError) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade800, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('残高の取得に失敗しました',
                          style: TextStyle(color: Colors.red.shade800)),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data ?? {'available': 0, 'pending': 0};
            final available = data['available'] ?? 0;
            final pending = data['pending'] ?? 0;

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SalesDashboardScreen()),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade800, Colors.blue.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade200.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stripe残高 (振込可能)',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '¥$available',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Stripe入金予定 ¥$pending',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
