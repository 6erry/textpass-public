import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class StripeService {
  static final StripeService _instance = StripeService._internal();

  factory StripeService() {
    return _instance;
  }

  StripeService._internal();

  Future<void> initialize() async {
    Stripe.publishableKey = 'pk_test_replace_me';
    Stripe.merchantIdentifier = 'merchant.com.example.textpass';
    await Stripe.instance.applySettings();
  }

  Future<String> createConnectAccount() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createConnectAccount')
          .call();
      return result.data['accountId'];
    } catch (e) {
      throw Exception('Failed to create connect account: $e');
    }
  }

  Future<String> createAccountLink(String accountId) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createAccountLink')
          .call({'accountId': accountId});
      return result.data['url'];
    } catch (e) {
      throw Exception('Failed to create account link: $e');
    }
  }

  Future<String> initPaymentSheet({
    required String bookId,
    required int amount,
    required String currency,
    required String connectedAccountId,
  }) async {
    try {
      // 1. Create PaymentIntent on the backend
      final result = await FirebaseFunctions.instance
          .httpsCallable('createPaymentIntent')
          .call({
        'bookId': bookId,
        'amount': amount,
        'currency': currency,
        'connectedAccountId': connectedAccountId,
      });

      final data = result.data;
      final clientSecret = data['paymentIntent'];
      final ephemeralKey = data['ephemeralKey'];
      final customerId = data['customer'];

      // Extract PaymentIntent ID from Client Secret (pi_xxx_secret_xxx -> pi_xxx)
      final paymentIntentId = (clientSecret as String).split('_secret_')[0];

      // 2. Initialize PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          customFlow: false,
          merchantDisplayName: 'TextPass',
          paymentIntentClientSecret: clientSecret,
          customerEphemeralKeySecret: ephemeralKey,
          customerId: customerId,
          style: ThemeMode.light,
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'JP',
            testEnv: true,
          ),
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'JP',
          ),
        ),
      );

      return paymentIntentId;
    } on FirebaseFunctionsException catch (e) {
      // print('Cloud Function Error: ${e.code}');
      // print('Message: ${e.message}');
      // print('Details: ${e.details}');
      throw Exception('Payment init failed: ${e.message} (${e.code})');
    } catch (e) {
      throw Exception('Failed to initialize payment sheet: $e');
    }
  }

  Future<Map<String, dynamic>> initBundlePaymentSheet({
    required String bundleRequestId,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createBundlePaymentIntent')
          .call({'bundleRequestId': bundleRequestId});

      final data = Map<String, dynamic>.from(result.data as Map);
      final clientSecret = data['paymentIntent'] as String;
      final ephemeralKey = data['ephemeralKey'] as String;
      final customerId = data['customer'] as String;
      final paymentIntentId = clientSecret.split('_secret_')[0];

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          customFlow: false,
          merchantDisplayName: 'TextPass',
          paymentIntentClientSecret: clientSecret,
          customerEphemeralKeySecret: ephemeralKey,
          customerId: customerId,
          style: ThemeMode.light,
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'JP',
            testEnv: true,
          ),
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'JP',
          ),
        ),
      );

      return {
        ...data,
        'paymentIntentId': paymentIntentId,
      };
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Bundle payment init failed: ${e.message} (${e.code})');
    } catch (e) {
      throw Exception('Failed to initialize bundle payment sheet: $e');
    }
  }

  Future<String> completeBundlePurchase({
    required String bundleRequestId,
    required String paymentIntentId,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('completeBundlePurchase')
        .call({
      'bundleRequestId': bundleRequestId,
      'paymentIntentId': paymentIntentId,
    });
    return result.data['chatRoomId'] as String;
  }

  Future<void> releaseBundleReservation(String bundleRequestId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('releaseBundleReservation')
          .call({'bundleRequestId': bundleRequestId});
    } catch (_) {
      // Reservation release is best-effort; server-side status checks remain authoritative.
    }
  }

  Future<void> refundTransaction(String chatRoomId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refundPayment')
          .call({'chatRoomId': chatRoomId});
    } catch (e) {
      throw Exception('Failed to process refund: $e');
    }
  }

  Future<void> releasePaymentHold({
    required String bookId,
    required String paymentIntentId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('releasePaymentHold')
          .call({
        'bookId': bookId,
        'paymentIntentId': paymentIntentId,
      });
    } catch (_) {
      // The hold expires server-side, so a best-effort release is enough here.
    }
  }

  Future<void> presentPaymentSheet() async {
    await Stripe.instance.presentPaymentSheet();
  }

  Future<String> createStripeLoginLink() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createStripeLoginLink')
          .call();
      return result.data['url'];
    } catch (e) {
      throw Exception('Failed to create login link: $e');
    }
  }

  Future<Map<String, dynamic>> getAccountBalance() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getAccountBalance')
          .call();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw Exception('Failed to get account balance: $e');
    }
  }

  Future<bool> isAccountOnboarded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      // Check for a flag like 'stripeAccountId' and 'chargesEnabled'
      // This data should be synced from Stripe via Webhooks to Firestore
      if (data?['stripeAccountId'] != null ||
          data?['stripeConnectedAccountId'] != null) {
        return true;
      }
      return data?['isStripeOnboarded'] == true;
    } catch (e) {
      return false;
    }
  }
}
