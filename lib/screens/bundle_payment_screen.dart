import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/book.dart';
import '../services/stripe_service.dart';
import '../utils/legal_notices.dart';
import 'transaction_screen.dart';
import 'package:textpass/utils/app_toast.dart';

class BundlePaymentScreen extends StatefulWidget {
  const BundlePaymentScreen({
    super.key,
    required this.bundleRequestId,
    required this.books,
  });

  final String bundleRequestId;
  final List<Book> books;

  @override
  State<BundlePaymentScreen> createState() => _BundlePaymentScreenState();
}

class _BundlePaymentScreenState extends State<BundlePaymentScreen> {
  bool _isLoading = true;
  bool _paymentSucceeded = false;
  String? _paymentIntentId;
  String? _errorMessage;
  int _itemAmount = 0;
  int _buyerFee = 0;

  @override
  void initState() {
    super.initState();
    _initPayment();
  }

  @override
  void dispose() {
    if (!_paymentSucceeded) {
      unawaited(
          StripeService().releaseBundleReservation(widget.bundleRequestId));
    }
    super.dispose();
  }

  Future<void> _initPayment() async {
    try {
      final data = await StripeService().initBundlePaymentSheet(
        bundleRequestId: widget.bundleRequestId,
      );
      if (!mounted) return;
      setState(() {
        _paymentIntentId = data['paymentIntentId'] as String;
        _itemAmount = (data['itemAmount'] as num).toInt();
        _buyerFee = (data['buyerFee'] as num).toInt();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '支払いの準備に失敗しました。商品状態を確認してください。';
      });
    }
  }

  Future<void> _pay() async {
    if (_paymentIntentId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await StripeService().presentPaymentSheet();
      if (!mounted) return;
      setState(() => _paymentSucceeded = true);
      final chatRoomId = await StripeService().completeBundlePurchase(
        bundleRequestId: widget.bundleRequestId,
        paymentIntentId: _paymentIntentId!,
      );
      if (!mounted) return;
      AppToast.show(context, '支払いが完了しました');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => TransactionScreen(
            chatRoomId: chatRoomId,
            book: widget.books.first,
          ),
        ),
        (route) => route.isFirst,
      );
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        await StripeService().releaseBundleReservation(widget.bundleRequestId);
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _paymentIntentId = null;
          _errorMessage = '決済をキャンセルしたため、商品の確保を解除しました。必要な場合は再度まとめ買いを依頼してください。';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '決済エラー: ${e.error.localizedMessage}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _paymentSucceeded
            ? '支払いは完了していますが、取引チャットの作成に失敗しました。時間をおいて再試行してください。'
            : '支払いに失敗しました。時間をおいて再試行してください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _itemAmount + _buyerFee;
    return Scaffold(
      appBar: AppBar(title: const Text('まとめ買い決済')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.books.length}冊をまとめて購入',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...widget.books.map((book) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(book.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('¥${book.price}'),
              )),
          const Divider(height: 32),
          _buildPriceRow('商品合計', _itemAmount),
          const SizedBox(height: 8),
          _buildPriceRow('システム利用料', _buyerFee),
          const Divider(height: 32),
          _buildPriceRow('支払総額', total, isTotal: true),
          const SizedBox(height: 16),
          const Text(
            'この決済中は、対象商品が一時的に確保されています。画面を閉じるか決済をキャンセルすると確保は解除されます。',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const InformationCard(
            title: '受け渡しについて',
            message: handoverSafetyNotice,
            icon: Icons.place_outlined,
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800),
                textAlign: TextAlign.center,
              ),
            ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(
              onPressed: _paymentIntentId == null ? null : _pay,
              child: const Text('まとめて購入する'),
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
            fontSize: isTotal ? 18 : 15,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '¥$amount',
          style: TextStyle(
            fontSize: isTotal ? 18 : 15,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
