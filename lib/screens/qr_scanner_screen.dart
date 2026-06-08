import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:textpass/utils/app_toast.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key, required this.expectedData});

  final String expectedData;

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRコードをスキャン'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _handleDetection,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Text(
                '購入者が商品状態を確認したうえでQRを提示していることを確認してください。QR完了後は取引完了として扱われます。',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;

    String? data;
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final value = barcode.rawValue;
      if (value == null) continue;
      data = value;
      break;
    }

    if (data == null) return;

    _isProcessing = true;

    if (data != widget.expectedData) {
      if (mounted) {
        AppToast.show(context, '無効なQRコードです');
      }
      _isProcessing = false;
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.expectedData)
          .update({
        'buyerConfirmed': true,
        'sellerConfirmed': true,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      AppToast.show(context, '更新に失敗しました: ${e.message ?? '不明なエラー'}');
      _isProcessing = false;
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '更新に失敗しました。');
      _isProcessing = false;
    }
  }
}
