import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'registration_screen.dart';
import 'login_screen.dart';
import 'package:textpass/widgets/auth_gate.dart';
import 'package:textpass/utils/app_toast.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = false;

  void _navigateToEmailRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
    );
  }

  void _navigateToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // --- Social Login Logic (Duplicated from LoginScreen for independence) ---

  // Helper functions for Apple Sign In
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofNonce(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    // print('WelcomeScreen: Apple Sign-In Started');
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofNonce(rawNonce);
      // print('WelcomeScreen: Nonce generated. calling getAppleIDCredential...');

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
        // Android requires webAuthenticationOptions
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: 'com.rynk.tekipa.service',
          redirectUri: Uri.parse(
            'https://your-firebase-project-id.firebaseapp.com/__/auth/handler',
          ),
        ),
      );
      // print('WelcomeScreen: Apple ID Credential received');

      final oAuthCredential = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
        rawNonce: rawNonce,
      );

      // print('WelcomeScreen: calling _handleSocialLogin');
      await _handleSocialLogin(oAuthCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      // print('WelcomeScreen: Apple Sign-In Exception: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e.code == AuthorizationErrorCode.canceled) {
        return;
      }
      _showSnackBar('Appleログインに失敗しました: ${e.message}', isError: true);
    } catch (e) {
      // print('WelcomeScreen: Apple Sign-In Generic Error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      final errorString = e.toString();
      if (errorString.contains('1000') || errorString.contains('canceled')) {
        return;
      }
      _showSnackBar('Appleログインに失敗しました: $e', isError: true);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _handleSocialLogin(credential);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Googleログインに失敗しました: $e', isError: true);
    }
  }

  Future<void> _handleSocialLogin(AuthCredential credential) async {
    try {
      // print('WelcomeScreen: _handleSocialLogin start');
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      // print(
      //     'WelcomeScreen: Firebase signIn success. User: ${userCredential.user?.uid}');

      final user = userCredential.user;

      if (user == null) throw Exception('User is null');

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      // print('WelcomeScreen: Firestore doc exists? ${doc.exists}');

      if (!doc.exists) {
        // print('WelcomeScreen: Creating new user record');
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isProfileComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
          'email': user.email,
        });
      }
      // print(
      //     'WelcomeScreen: _handleSocialLogin complete. Resetting to AuthGate...');

      if (!mounted) return;
      // Explicitly navigate to AuthGate to ensure widget tree is correct
      // This handles cases where WelcomeScreen was pushed directly (removing AuthGate)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      // print('WelcomeScreen: _handleSocialLogin Error: $e');
      if (!mounted) return;
      _showSnackBar('ログイン処理に失敗しました: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppToast.showError(context, message);
    } else {
      AppToast.showSuccess(context, message);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    // Access theme colors
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        // title: const Text('会員登録', style: TextStyle(fontWeight: FontWeight.bold)),
        // Removed generic title to focus on Branding
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Branding / Logo
                // Use asset logo, fallback to icon
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Image.asset(
                    'assets/logo.png',
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.menu_book_rounded,
                          size: 80, color: primaryColor);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tekipa', // Updated Name
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '教科書売買・大学生活インフラ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 48),

                _buildButton(
                  onPressed: _navigateToEmailRegistration,
                  icon: Icons.mail_outline,
                  label: 'メールアドレスで登録',
                ),
                const SizedBox(height: 16),
                _buildButton(
                  onPressed: _signInWithApple,
                  icon: Icons.apple,
                  label: 'Appleで登録', // Changed to "Register" for consistency
                ),
                const SizedBox(height: 16),
                _buildWidgetButton(
                  onPressed: _signInWithGoogle,
                  icon: SvgPicture.asset(
                    'assets/google_logo.svg',
                    width: 24,
                    height: 24,
                  ),
                  label: 'Googleで登録',
                ),
                const SizedBox(height: 48),

                // Login Section
                const Text(
                  'すでにアカウントをお持ちの方',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _isLoading ? null : _navigateToLogin,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: primaryColor),
                    foregroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(30), // More modern/app-like
                    ),
                  ),
                  child: const Text('ログイン',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return OutlinedButton(
      onPressed: _isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, size: 24, color: Colors.black),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 40), // Balance icon width
        ],
      ),
    );
  }

  Widget _buildWidgetButton({
    required VoidCallback onPressed,
    required Widget icon,
    required String label,
  }) {
    return OutlinedButton(
      onPressed: _isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          SizedBox(width: 24, child: icon),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 40), // Balance icon width
        ],
      ),
    );
  }
}
