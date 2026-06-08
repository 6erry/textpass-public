import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import 'book_detail_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class BundleRequestScreen extends StatefulWidget {
  const BundleRequestScreen({super.key, required this.initialBook});

  final Book initialBook;

  @override
  State<BundleRequestScreen> createState() => _BundleRequestScreenState();
}

class _BundleRequestScreenState extends State<BundleRequestScreen> {
  final _messageController = TextEditingController();
  final Set<String> _selectedBookIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<Book> _books = [];

  @override
  void initState() {
    super.initState();
    _selectedBookIds.add(widget.initialBook.id);
    _loadBooks();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('books')
          .where('userId', isEqualTo: widget.initialBook.userId)
          .where('status', isEqualTo: 'available')
          .get()
          .timeout(const Duration(seconds: 12));
      final books = snapshot.docs.map((doc) => Book.fromFirestore(doc)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _books = books;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _books = [widget.initialBook];
        _isLoading = false;
        _errorMessage = '同じ出品者の商品を取得できませんでした。通信状況を確認して再読み込みしてください。';
      });
    }
  }

  int get _totalPrice => _books
      .where((book) => _selectedBookIds.contains(book.id))
      .fold(0, (total, book) => total + book.price);

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'ログインが必要です');
      return;
    }
    if (_selectedBookIds.length < 2) {
      AppToast.show(context, '2冊以上選択してください');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('createBundleRequest')
          .call({
        'bookIds': _selectedBookIds.toList(),
        'buyerMessage': _messageController.text.trim(),
      });
      if (!mounted) return;
      AppToast.show(context, 'まとめ買い依頼を送信しました');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.show(context, '送信に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('まとめ買い依頼')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _BundleRequestErrorState(
                  message: _errorMessage!,
                  onRetry: _loadBooks,
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                            '同じ出品者の商品を選択',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '依頼中の商品はまだ確保されません。出品者が承認すると、決済用に一定時間だけ確保されます。',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 16),
                          ..._books.map(_buildBookTile),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _messageController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: '出品者へのメッセージ（任意）',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selectedBookIds.length}冊 / ¥$_totalPrice',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('依頼する'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBookTile(Book book) {
    final selected = _selectedBookIds.contains(book.id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(
              book: book,
              bundleSelectionMode: true,
              isSelectedForBundle: selected,
              onBundleSelectionChanged: (isSelected) {
                if (!mounted) return;
                setState(() {
                  if (isSelected) {
                    _selectedBookIds.add(book.id);
                  } else {
                    _selectedBookIds.remove(book.id);
                  }
                });
              },
            ),
          ),
        );
      },
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: book.imageUrls.isEmpty
            ? Container(
                width: 48,
                height: 48,
                color: Colors.grey.shade200,
                child: const Icon(Icons.menu_book_outlined),
              )
            : Image.network(
                book.imageUrls.first,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
      ),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('¥${book.price}'),
      trailing: Checkbox(
        value: selected,
        onChanged: (value) {
          setState(() {
            if (value == true) {
              _selectedBookIds.add(book.id);
            } else {
              _selectedBookIds.remove(book.id);
            }
          });
        },
      ),
    );
  }
}

class _BundleRequestErrorState extends StatelessWidget {
  const _BundleRequestErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 36,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
