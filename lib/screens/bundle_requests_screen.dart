import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import 'bundle_payment_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class BundleRequestsScreen extends StatefulWidget {
  const BundleRequestsScreen({super.key});

  @override
  State<BundleRequestsScreen> createState() => _BundleRequestsScreenState();
}

class _BundleRequestsScreenState extends State<BundleRequestsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _requests = [];
  Timer? _reservationTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _reservationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reservationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'ログイン状態を確認できませんでした。再ログインしてください。';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('bundle_requests')
            .where('buyerId', isEqualTo: uid)
            .get(),
        FirebaseFirestore.instance
            .collection('bundle_requests')
            .where('sellerId', isEqualTo: uid)
            .get(),
      ]).timeout(const Duration(seconds: 12));
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final doc in [...results[0].docs, ...results[1].docs]) {
        byId[doc.id] = doc;
      }
      final docs = byId.values.toList()
        ..sort((a, b) {
          final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      if (!mounted) return;
      setState(() {
        _requests = docs;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requests = [];
        _isLoading = false;
        _errorMessage = 'まとめ買い依頼を取得できませんでした。通信状況を確認して再読み込みしてください。';
      });
    }
  }

  Future<List<Book>> _loadBooks(List<dynamic> ids) async {
    final refs = ids
        .map((id) => FirebaseFirestore.instance.collection('books').doc('$id'))
        .toList();
    final docs = await Future.wait(refs.map((ref) => ref.get()));
    return docs
        .where((doc) => doc.exists)
        .map((doc) => Book.fromFirestore(doc))
        .toList();
  }

  Future<void> _respond(String id, String action, int total) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('respondBundleRequest')
          .call({
        'bundleRequestId': id,
        'action': action,
        'proposedTotalPrice': total,
      });
      if (!mounted) return;
      AppToast.show(context, action == 'accepted' ? '承認しました' : '拒否しました');
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, '操作に失敗しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('まとめ買い依頼')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _BundleRequestErrorState(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _requests.isEmpty
                      ? const Center(child: Text('まとめ買い依頼はありません'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            final doc = _requests[index];
                            final data = doc.data();
                            final isSeller = data['sellerId'] == uid;
                            return _BundleRequestCard(
                              requestId: doc.id,
                              data: data,
                              isSeller: isSeller,
                              loadBooks: _loadBooks,
                              onRespond: _respond,
                            );
                          },
                        ),
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

class _BundleRequestCard extends StatelessWidget {
  const _BundleRequestCard({
    required this.requestId,
    required this.data,
    required this.isSeller,
    required this.loadBooks,
    required this.onRespond,
  });

  final String requestId;
  final Map<String, dynamic> data;
  final bool isSeller;
  final Future<List<Book>> Function(List<dynamic> ids) loadBooks;
  final Future<void> Function(String id, String action, int total) onRespond;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final total = data['proposedTotalPrice'] as int? ?? 0;
    final ids = List<dynamic>.from(data['bookIds'] ?? []);
    final reservedUntil = (data['reservedUntil'] as Timestamp?)?.toDate();
    final reservationExpired = status == 'accepted' &&
        reservedUntil != null &&
        !reservedUntil.isAfter(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<List<Book>>(
          future: loadBooks(ids),
          builder: (context, snapshot) {
            final books = snapshot.data ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${books.length}冊のまとめ買い依頼',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text('状態: ${_statusLabel(status)} / 合計 ¥$total'),
                if (status == 'accepted' && reservedUntil != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    reservationExpired
                        ? '確保期限が切れています。'
                        : '${_formatDateTime(reservedUntil)}まで決済用に確保中（${_remainingText(reservedUntil)}）',
                    style: TextStyle(
                      color: reservationExpired
                          ? Colors.red.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
                if ((data['buyerMessage'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('メッセージ: ${data['buyerMessage']}'),
                ],
                const SizedBox(height: 8),
                ...books.take(4).map((book) => Text(
                      '- ${book.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                if (books.length > 4) Text('ほか${books.length - 4}冊'),
                const SizedBox(height: 12),
                if (isSeller && status == 'pending')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '承認すると、対象商品は購入者の決済用に一時的に確保されます。',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  onRespond(requestId, 'rejected', total),
                              child: const Text('拒否'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  onRespond(requestId, 'accepted', total),
                              child: const Text('承認'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (!isSeller && status == 'accepted')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: books.isEmpty || reservationExpired
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BundlePaymentScreen(
                                    bundleRequestId: requestId,
                                    books: books,
                                  ),
                                ),
                              );
                            },
                      child: const Text('まとめて決済する'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '承認待ち';
      case 'accepted':
        return '承認済み';
      case 'rejected':
        return '拒否';
      case 'paid':
        return '支払い済み';
      case 'expired':
        return '期限切れ';
      case 'cancelled':
        return 'キャンセル';
      default:
        return status;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String _remainingText(DateTime dateTime) {
    final remaining = dateTime.difference(DateTime.now());
    if (remaining.isNegative) return '期限切れ';
    final minutes = remaining.inMinutes;
    if (minutes < 1) return 'まもなく解除';
    if (minutes < 60) return 'あと$minutes分';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'あと$hours時間' : 'あと$hours時間$rest分';
  }
}
