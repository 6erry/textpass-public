import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../services/stripe_service.dart';
import '../utils/legal_notices.dart';
import 'transaction_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  bool _isLoading = true; // Start loading initially
  bool _paymentSucceeded = false;
  String? _errorMessage;
  String? _connectedAccountId;
  String? _paymentIntentId;
  bool _showFirstTransactionGuide = false;

  @override
  void initState() {
    super.initState();
    _loadFirstTransactionGuideState();
    _fetchSellerStripeAccount();
  }

  Future<void> _loadFirstTransactionGuideState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('firstTransactionGuideSeen') ?? false;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final transactionCount =
        (userDoc.data()?['transactionCount'] as num?)?.toInt() ?? 0;
    if (!mounted) return;
    setState(() {
      _showFirstTransactionGuide = !seen && transactionCount == 0;
    });
  }

  Future<void> _dismissFirstTransactionGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firstTransactionGuideSeen', true);
    if (!mounted) return;
    setState(() => _showFirstTransactionGuide = false);
  }

  @override
  void dispose() {
    final paymentIntentId = _paymentIntentId;
    if (!_paymentSucceeded && paymentIntentId != null) {
      unawaited(StripeService().releasePaymentHold(
        bookId: widget.book.id,
        paymentIntentId: paymentIntentId,
      ));
    }
    super.dispose();
  }

  Future<void> _fetchSellerStripeAccount() async {
    try {
      final validationMessage = await _validateBookBeforePayment();
      if (validationMessage != null) {
        await _releasePaymentHoldSilently();
        _showBlockingError(validationMessage);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.book.userId)
          .get();

      if (!mounted) return;

      final data = userDoc.data();
      final accountId = data?['stripeAccountId'] as String? ??
          data?['stripeConnectedAccountId'] as String?;
      if (accountId != null) {
        setState(() {
          _connectedAccountId = accountId;
        });
        await _initPayment(); // Await initialization
      } else {
        setState(() {
          _errorMessage = '出品者が支払い設定を完了していません';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '出品者情報の取得に失敗しました';
        _isLoading = false;
      });
    }
  }

  Future<void> _initPayment() async {
    if (_connectedAccountId == null) return;

    try {
      final validationMessage = await _validateBookBeforePayment();
      if (validationMessage != null) {
        _showBlockingError(validationMessage);
        return;
      }

      final paymentIntentId = await StripeService().initPaymentSheet(
        bookId: widget.book.id,
        amount: widget.book.price,
        currency: 'jpy',
        connectedAccountId: _connectedAccountId!,
      );

      if (!mounted) return;

      setState(() {
        _paymentIntentId = paymentIntentId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyPaymentError(e);
      });
    }
  }

  Future<String?> _validateBookBeforePayment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return '購入するにはログインが必要です。';
    }

    final doc = await FirebaseFirestore.instance
        .collection('books')
        .doc(widget.book.id)
        .get();
    if (!doc.exists) {
      return '商品が見つかりませんでした。すでに削除された可能性があります。';
    }

    final data = doc.data();
    final status = data?['status']?.toString();
    if (status != null && status != 'available') {
      return 'この商品はすでに購入済み、または出品が停止されています。';
    }
    final moderationStatus = data?['moderationStatus']?.toString() ?? 'active';
    if (moderationStatus != 'active') {
      return 'この商品は現在購入できません。';
    }
    if (data?['prohibitedCheckConfirmed'] == false) {
      return 'この商品は出品確認が完了していないため、現在購入できません。';
    }
    final purchaseMode =
        data?['purchaseMode']?.toString() ?? widget.book.purchaseMode;
    if (purchaseMode == purchaseModeApprovalRequired) {
      final requestDoc = await FirebaseFirestore.instance
          .collection('purchase_requests')
          .doc('${widget.book.id}_${currentUser.uid}')
          .get();
      final requestData = requestDoc.data();
      if (!requestDoc.exists || requestData?['status'] != 'approved') {
        return 'この商品は購入前に出品者の承認が必要です。商品詳細から購入申請を送ってください。';
      }
    }

    final sellerId = data?['userId']?.toString() ?? '';
    if (sellerId.isEmpty) {
      return '出品者情報を確認できませんでした。';
    }
    if (sellerId == currentUser.uid) {
      return '自分が出品した商品は購入できません。';
    }

    final currentPrice = _readInt(data?['price']);
    if (currentPrice == null || currentPrice <= 0) {
      return '商品の価格情報を確認できませんでした。';
    }
    if (currentPrice != widget.book.price) {
      return '商品の価格が更新されています。商品ページに戻って確認してください。';
    }

    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _showBlockingError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  Future<void> _handlePurchase() async {
    if (_paymentIntentId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final validationMessage = await _validateBookBeforePayment();
      if (validationMessage != null) {
        _showBlockingError(validationMessage);
        return;
      }

      // 1. Execute Payment
      await StripeService().presentPaymentSheet();

      if (!mounted) return;
      setState(() {
        _paymentSucceeded = true;
      });

      // 2. Process Post-Payment Logic
      await _completePurchase();
    } on StripeException catch (e) {
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        await _releasePaymentHoldSilently();
        if (!mounted) return;
        setState(() {
          _isLoading = true;
          _errorMessage = null; // Clear error on cancel
        });
        await _initPayment();
        return;
      }
      await _releasePaymentHoldSilently();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '決済エラー: ${e.error.localizedMessage}';
      });
    } catch (e) {
      if (!mounted) return;
      await _releasePaymentHoldSilently();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyPaymentError(e);
      });
    }
  }

  Future<void> _completePurchase() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('completeBookPurchase')
          .call({
        'bookId': widget.book.id,
        'paymentIntentId': _paymentIntentId!,
      });
      final chatRoomId = result.data['chatRoomId'] as String?;
      if (chatRoomId == null || chatRoomId.isEmpty) {
        throw Exception('取引ルームの作成に失敗しました');
      }

      if (!mounted) return;

      AppToast.show(context, '支払いが完了しました！取引チャットへ移動します。');

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => TransactionScreen(
            chatRoomId: chatRoomId,
            book: widget.book,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyPaymentError(
          e,
          fallback: '支払いは完了していますが、取引チャットの作成に失敗しました。時間をおいて再試行してください。',
        );
      });
    }
  }

  Future<void> _releasePaymentHoldSilently() async {
    final paymentIntentId = _paymentIntentId;
    if (paymentIntentId == null || _paymentSucceeded) return;
    await StripeService().releasePaymentHold(
      bookId: widget.book.id,
      paymentIntentId: paymentIntentId,
    );
    _paymentIntentId = null;
  }

  @override
  Widget build(BuildContext context) {
    final buyerFee = widget.book.buyerFee;
    final sellerFee = (widget.book.price * widget.book.feeRate).floor();
    final feePercent = (widget.book.feeRate * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('購入手続き')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Item Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: widget.book.imageUrls.isNotEmpty
                      ? Image.network(
                          widget.book.imageUrls.first,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.book.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(_formatYen(widget.book.price)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            // Price Breakdown
            const Text(
              '支払い金額',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildPriceRow('商品価格', widget.book.price),
            const SizedBox(height: 8),
            _buildPriceRow('システム利用料', buyerFee),
            const Divider(height: 32),
            _buildPriceRow('支払総額', widget.book.price + buyerFee, isTotal: true),
            const SizedBox(height: 12),
            Text(
              '${listingTypeLabels[widget.book.listingType] ?? 'このカテゴリ'}は販売手数料$feePercent%（売り手負担: ${_formatYen(sellerFee)}）です。手渡しだから送料もかかりません。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),

            const SizedBox(height: 24),
            _buildPurchaseFlowNotice(),
            if (_showFirstTransactionGuide) ...[
              const SizedBox(height: 16),
              _buildFirstTransactionGuide(),
            ],
            const SizedBox(height: 16),
            const InformationCard(
              title: '受け渡しについて',
              message: handoverSafetyNotice,
              icon: Icons.place_outlined,
            ),

            const SizedBox(height: 32),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.shade50,
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                  textAlign: TextAlign.center,
                ),
              ),

            // Action Button
            if (_isLoading)
              _buildPaymentLoadingNotice()
            else if (_paymentSucceeded)
              _buildPaymentSucceededRetryButton()
            else
              ElevatedButton(
                onPressed:
                    (_connectedAccountId == null || _paymentIntentId == null)
                        ? null
                        : _handlePurchase,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.red, // Mercari-like red
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey,
                ),
                child: const Text(
                  '購入する',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              '※ 支払い方法は次のStripe画面で選択できます。\n※ 購入ボタンを押すと、支払い手続きに進みます。\n※ 支払い完了後、取引チャットで受け渡し場所を相談してください。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSucceededRetryButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade100),
          ),
          child: Text(
            '支払いは完了しています。通信状況などで取引チャット作成に失敗した場合は、下のボタンで再開できます。',
            style: TextStyle(color: Colors.green.shade900, fontSize: 13),
          ),
        ),
        ElevatedButton(
          onPressed: _completePurchase,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text(
            '取引チャットへ進む',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseFlowNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '購入後の流れ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildFlowStep(Icons.payment_outlined, 'Stripe画面で支払う'),
          _buildFlowStep(Icons.chat_bubble_outline, '取引チャットで受け渡し場所を決める'),
          _buildFlowStep(Icons.check_circle_outline, '受け渡し後に取引完了'),
        ],
      ),
    );
  }

  Widget _buildFirstTransactionGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '初めての取引でも大丈夫です',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildFlowStep(Icons.chat_bubble_outline, 'アプリ内チャットで日時を相談'),
          _buildFlowStep(Icons.people_outline, '安全のため人目のある場所で受け渡し'),
          _buildFlowStep(Icons.fact_check_outlined, '商品の状態をその場で確認'),
          _buildFlowStep(Icons.qr_code_2_outlined, '問題なければQRで取引完了'),
          _buildFlowStep(Icons.report_problem_outlined, '困ったときは通報・相談できます'),
          const SizedBox(height: 8),
          Text(
            '個人情報を直接交換する必要はありません。大学施設、店舗、公共施設などを利用する場合は、各施設のルールに従ってください。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _dismissFirstTransactionGuide,
              child: const Text('理解しました'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentLoadingNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 14),
          Text(
            '安全な支払いのため、Stripe（決済サービス）を呼び出しています。',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'カード情報などの決済情報はTekipa側には一切記録されません。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, int amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          _formatYen(amount),
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  String _formatYen(int amount) {
    final raw = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(raw[i]);
    }
    return '¥$buffer';
  }

  String _friendlyPaymentError(Object error, {String? fallback}) {
    final message = error.toString();

    if (message.contains('seller cannot buy own item')) {
      return '自分が出品した商品は購入できません。';
    }
    if (message.contains('book not found')) {
      return '商品が見つかりませんでした。すでに削除された可能性があります。';
    }
    if (message.contains('item is not available')) {
      return 'この商品はすでに購入済み、または出品が停止されています。';
    }
    if (message.contains('item is being purchased')) {
      return 'この商品は他のユーザーが購入手続き中です。少し時間をおいて確認してください。';
    }
    if (message.contains('item price changed')) {
      return '商品の価格が更新されています。商品ページに戻って確認してください。';
    }
    if (message.contains('seller stripe account not found')) {
      return '出品者が支払い設定を完了していないため、現在は購入できません。';
    }
    if (message.contains('Seller account is not ready') ||
        message.contains('account_inactive')) {
      return '出品者の本人確認（売上振込申請）が完了していないため、現在は購入できません。出品者にコメントで確認してください。';
    }
    if (message.contains('payment is not completed')) {
      return '支払いが完了していません。もう一度購入手続きを行ってください。';
    }
    if (message.contains('network') ||
        message.contains('unavailable') ||
        message.contains('deadline-exceeded')) {
      return '通信状態を確認して、もう一度お試しください。';
    }

    return fallback ?? '支払いの準備に失敗しました。時間をおいてもう一度お試しください。';
  }
}
