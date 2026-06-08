import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:textpass/utils/app_toast.dart';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('メールアドレスとパスワードを入力してください。', isError: true);
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // print('LoginScreen: Login successful'); // Debug log
      if (!mounted) return;
      _showSnackBar('ログインしました。'); // Default isSuccess
      // Pop until the first route (MainScreen via AuthGate)
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'ログインに失敗しました。';
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'ユーザーが見つかりません。';
          break;
        case 'wrong-password':
          errorMessage = 'パスワードが間違っています。';
          break;
        case 'invalid-email':
          errorMessage = 'メールアドレスの形式が正しくありません。';
          break;
        case 'user-disabled':
          errorMessage = 'このユーザーは無効化されています。';
          break;
        case 'invalid-credential':
          errorMessage = 'メールアドレスまたはパスワードが間違っています。';
          break;
        default:
          errorMessage = 'エラーが発生しました: ${e.code}';
      }
      _showSnackBar(errorMessage, isError: true);
    } catch (_) {
      _showSnackBar('ログインに失敗しました。', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // _navigateToRegistration removed as LoginScreen is now standalone.

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // Canceled by user
        setState(() {
          _isLoading = false;
        });
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
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Googleログインに失敗しました: $e', isError: true);
    }
  }

  // Helper functions for Apple Sign In with Firebase
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
    setState(() {
      _isLoading = true;
    });
    try {
      // print('Apple Sign-In: Starting...');
      final rawNonce = _generateNonce();
      final nonce = _sha256ofNonce(rawNonce);
      // print('Apple Sign-In: Nonce generated. calling getAppleIDCredential...');

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce, // Pass SHA256 nonce to Apple
        // Android requires webAuthenticationOptions
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: 'com.rynk.tekipa.service',
          redirectUri: Uri.parse(
            'https://your-firebase-project-id.firebaseapp.com/__/auth/handler',
          ),
        ),
      );

      // print('Apple Sign-In: Credential received from Apple.');

      final oAuthCredential = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
        rawNonce: rawNonce, // Pass raw nonce to Firebase
      );

      // print('Apple Sign-In: Firebase Credential created. Signing in...');

      await _handleSocialLogin(oAuthCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      // Cancelled by user
      if (e.code == AuthorizationErrorCode.canceled) {
        return;
      }
      _showSnackBar('Appleログインに失敗しました: ${e.message}', isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      final errorString = e.toString();
      // Robust check for cancellation which might be wrapped in PlatformException
      if (errorString.contains('1000') || errorString.contains('canceled')) {
        return;
      }

      _showSnackBar('Appleログインに失敗しました: $e', isError: true);
    }
  }

  Future<void> _handleSocialLogin(AuthCredential credential) async {
    try {
      // print('SocialLogin: signInWithCredential start');
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      // print(
      //     'SocialLogin: signInWithCredential success. User: ${userCredential.user?.uid}');
      final user = userCredential.user;

      if (user == null) throw Exception('User is null');

      // Check if user exists in Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        // New User -> Initialize
        // Note: universityId is NOT set here. Logic moved to ProfileSetupScreen.
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isProfileComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
          'email': user.email, // Save initial email (e.g. gmail)
          'contactEmail': user.email, // Save as contact email by default
        });
      }

      // AuthGate will detect state change and navigate
      // Since LoginScreen is pushed from WelcomeScreen, we need to pop it to reveal the updated AuthGate (MainScreen).
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('ログイン処理に失敗しました: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController =
        TextEditingController(text: emailController.text.trim());
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('パスワード再設定'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('登録しているメールアドレスを入力してください。\nパスワード再設定用のリンクを送信します。'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    decoration: InputDecoration(
                      hintText: 'example@university.ac.jp',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!isSending) Navigator.pop(context);
                  },
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = resetEmailController.text.trim();
                          if (email.isEmpty) {
                            AppToast.showError(context, 'メールアドレスを入力してください。');
                            return;
                          }

                          setStateDialog(() {
                            isSending = true;
                          });

                          try {
                            await FirebaseAuth.instance
                                .sendPasswordResetEmail(email: email);
                            if (context.mounted) {
                              Navigator.pop(context); // Close dialog
                              AppToast.showSuccess(
                                  context, '再設定メールを送信しました。受信トレイをご確認ください。');
                            }
                          } on FirebaseAuthException catch (e) {
                            if (context.mounted) {
                              String errorMsg = '送信に失敗しました。';
                              if (e.code == 'user-not-found') {
                                errorMsg = 'このメールアドレスは登録されていません。';
                              } else if (e.code == 'invalid-email') {
                                errorMsg = '正しい形式でメールアドレスを入力してください。';
                              }
                              AppToast.showError(context, errorMsg);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              AppToast.showError(context, 'エラーが発生しました: $e');
                            }
                          } finally {
                            if (context.mounted) {
                              setStateDialog(() {
                                isSending = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('送信'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- UI Construction ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('ログイン', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'メールアドレス',
                      hintText: 'example@university.ac.jp',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12), // Softer radius
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'パスワード',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor:
                            Theme.of(context).colorScheme.primary, // App Theme
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('ログイン',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text('パスワードをお忘れの場合',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child:
                            Text('または', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Social Login Section
                  const Center(
                    child: Text(
                      'Google, Appleのアカウントで登録した場合はこちら',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSocialLoginButton(
                    onPressed: _signInWithApple,
                    icon: const Icon(
                      Icons.apple,
                      size: 24,
                      color: Colors.black,
                    ),
                    label: 'Appleでサインイン',
                    color: Colors.white,
                    textColor: Colors.black,
                    isOutlined: true,
                  ),
                  const SizedBox(height: 12),
                  _buildSocialLoginButton(
                    onPressed: _signInWithGoogle,
                    icon: SvgPicture.asset(
                      'assets/google_logo.svg',
                      width: 24,
                      height: 24,
                    ),
                    label: 'Googleでログイン',
                    color: Colors.white,
                    textColor: Colors.black,
                    isOutlined: true,
                  ),

                  // No "Register" button here as it's the specific Login screen
                ],
              ),
            ),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildSocialLoginButton({
    required VoidCallback onPressed,
    required Widget icon,
    required String label,
    required Color color,
    required Color textColor,
    bool isOutlined = false,
  }) {
    // Mercari style: Boxy, Outlined, simple
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: color,
          side: const BorderSide(color: Colors.grey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(width: 24, height: 24, child: icon),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 40), // Balance icon width
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppToast.showError(context, message);
    } else {
      AppToast.showSuccess(context, message);
    }
  }
}
