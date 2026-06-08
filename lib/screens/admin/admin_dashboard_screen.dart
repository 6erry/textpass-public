import 'package:flutter/material.dart';
import 'report_list_screen.dart';
import 'admin_user_list_screen.dart';
import 'create_announcement_screen.dart';
import 'pr_management_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理者ダッシュボード'),
      ),
      body: ListView(
        children: [
          _buildMenuItem(
            context,
            icon: Icons.report_problem,
            title: '通報一覧',
            subtitle: '未対応の通報を確認・対応します',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportListScreen()),
              );
            },
          ),
          const Divider(),
          _buildMenuItem(
            context,
            icon: Icons.people,
            title: 'ユーザー管理',
            subtitle: 'ユーザーの検索・詳細確認・BAN',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUserListScreen()),
              );
            },
          ),
          const Divider(),
          _buildMenuItem(
            context,
            icon: Icons.campaign,
            title: 'お知らせ作成',
            subtitle: '全ユーザー向けのお知らせを配信',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CreateAnnouncementScreen()),
              );
            },
          ),
          const Divider(),
          _buildMenuItem(
            context,
            icon: Icons.ads_click,
            title: 'PR表示管理',
            subtitle: '外部で成立した掲載を手動でPR表示にします',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrManagementScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        child: Icon(icon, color: Theme.of(context).primaryColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
