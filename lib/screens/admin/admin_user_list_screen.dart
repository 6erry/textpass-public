import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_custom_dialog.dart';
import 'package:textpass/utils/app_toast.dart';

class AdminUserListScreen extends StatefulWidget {
  const AdminUserListScreen({super.key});

  @override
  State<AdminUserListScreen> createState() => _AdminUserListScreenState();
}

class _AdminUserListScreenState extends State<AdminUserListScreen> {
  final _adminService = AdminService();
  final _searchController = TextEditingController();
  List<DocumentSnapshot<Map<String, dynamic>>> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResults = [];
    });

    try {
      final results = await _adminService.searchUser(query);
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _errorMessage = 'ユーザーが見つかりませんでした';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'エラー: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー管理'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'メールアドレス または UID',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 16),
            if (_isLoading) const CircularProgressIndicator(),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final userDoc = _searchResults[index];
                  final userData = userDoc.data()!;
                  final uid = userDoc.id;
                  final email = userData['email'] ?? 'No Email';
                  final isBanned = userData['isBanned'] == true;
                  final universityId = userData['universityId'] ?? 'N/A';

                  return Card(
                    child: ListTile(
                      title: Text(email),
                      subtitle: Text('UID: $uid\nUniv: $universityId'),
                      trailing: Switch(
                        value: isBanned,
                        onChanged: (value) =>
                            _confirmBanToggle(context, uid, value),
                        activeThumbColor: Colors.red,
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBanToggle(
      BuildContext context, String uid, bool newValue) async {
    final action = newValue ? 'BAN (利用停止)' : 'BAN解除';
    showDialog(
      context: context,
      builder: (context) => AppCustomDialog(
        title: '$actionの確認',
        message: '本当にこのユーザーを$actionしますか？',
        icon: newValue ? Icons.block : Icons.check_circle,
        confirmText: '実行',
        confirmColor: newValue ? Colors.red : Colors.green,
        onConfirm: () async {
          Navigator.pop(context);
          try {
            if (newValue) {
              await _adminService.banUser(uid);
            } else {
              await _adminService.unbanUser(uid);
            }
            // Refresh search results to update UI
            _search();
            if (context.mounted) {
              AppToast.show(context, 'ユーザーを$actionしました');
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(context, 'エラー: $e');
            }
          }
        },
      ),
    );
  }
}
