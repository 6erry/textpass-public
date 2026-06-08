import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:textpass/utils/app_toast.dart';

class KeywordAlertScreen extends StatefulWidget {
  const KeywordAlertScreen({super.key});

  @override
  State<KeywordAlertScreen> createState() => _KeywordAlertScreenState();
}

class _KeywordAlertScreenState extends State<KeywordAlertScreen> {
  final _keywordController = TextEditingController();
  final _user = FirebaseAuth.instance.currentUser;
  List<String> _keywords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadKeywords();
  }

  Future<void> _loadKeywords() async {
    if (_user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _keywords = List<String>.from(doc.data()?['alertKeywords'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      // print('Error loading keywords: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty || _user == null) return;

    if (_keywords.length >= 5) {
      AppToast.show(context, '登録できるキーワードは5つまでです');
      return;
    }

    if (_keywords.contains(keyword)) {
      AppToast.show(context, 'このキーワードは既に登録されています');
      return;
    }

    try {
      setState(() => _isLoading = true);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .update({
        'alertKeywords': FieldValue.arrayUnion([keyword]),
      });

      _keywordController.clear();
      await _loadKeywords();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'エラーが発生しました: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeKeyword(String keyword) async {
    if (_user == null) return;

    try {
      setState(() => _isLoading = true);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .update({
        'alertKeywords': FieldValue.arrayRemove([keyword]),
      });

      await _loadKeywords();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'エラーが発生しました: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('キーワード通知設定'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active,
                            color: Colors.blue.shade700, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '欲しい教科書を登録しよう！',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'キーワードを含む商品が出品されると、通知が届きます。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'キーワードを追加',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keywordController,
                          decoration: const InputDecoration(
                            hintText: '例: 線形代数, 物理学',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _addKeyword,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                        ),
                        child: const Text('追加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '登録済みキーワード',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  if (_keywords.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'まだ登録されていません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _keywords.map((keyword) {
                        return Chip(
                          label: Text(keyword),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeKeyword(keyword),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
    );
  }
}
