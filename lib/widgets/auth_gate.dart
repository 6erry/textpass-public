// ignore_for_file: prefer_const_constructors
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/profile_setup_screen.dart';
import '../screens/main_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/otp_verification_screen.dart';
import '../screens/university_email_required_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  bool _timestampIsFuture(Timestamp? timestamp) {
    return timestamp == null || timestamp.toDate().isAfter(DateTime.now());
  }

  Widget _buildProvisionalGate({
    required Map<String, dynamic>? userData,
    required bool isProfileComplete,
  }) {
    final userExpiresAt = userData?['provisionalExpiresAt'] as Timestamp?;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('app_config')
          .doc('registration')
          .snapshots(),
      builder: (context, configSnapshot) {
        if (configSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final config = configSnapshot.data?.data();
        final enabled = config?['freshmanProvisionalEnabled'] as bool? ?? false;
        final configExpiresAt =
            config?['freshmanProvisionalExpiresAt'] as Timestamp?;
        final isActive = enabled &&
            _timestampIsFuture(configExpiresAt) &&
            _timestampIsFuture(userExpiresAt);

        if (!isActive) {
          return const UniversityEmailRequiredScreen();
        }

        if (isProfileComplete) {
          return const MainScreen();
        }
        return const ProfileSetupScreen();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance
          .authStateChanges(), // Use authStateChanges to avoid rebuilds on reload()
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          return const WelcomeScreen();
        }

        // Fetch User Data *BEFORE* checking verification
        // This allows us to use 'isStudentVerified' from Firestore instead of just auth.emailVerified
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'ユーザー情報の取得に失敗しました。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text('ログイン画面に戻る'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = userSnapshot.data?.data();
            final isBanned = data?['isBanned'] as bool? ?? false;

            if (isBanned) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, size: 64, color: Colors.red),
                        const SizedBox(height: 24),
                        const Text(
                          'アカウントが停止されました',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '利用規約違反のため、このアカウントは利用停止されています。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('ログアウト'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Verification Check
            // We accept university-verified users, and temporarily allow
            // first-year provisional users while the server flag is enabled.
            final isFirebaseVerified = user.emailVerified;
            final isFirestoreVerified =
                data?['isStudentVerified'] as bool? ?? false;
            final hasUniversityIdentity =
                (data?['universityId'] as String?)?.isNotEmpty == true ||
                    (data?['universityEmail'] as String?)?.isNotEmpty == true;
            final hasVerifiedStudentIdentity = isFirestoreVerified ||
                (isFirebaseVerified && hasUniversityIdentity);
            final isFreshmanProvisional =
                data?['verificationStatus'] == 'provisional_freshman' ||
                    data?['isFreshmanProvisional'] == true;
            final isProfileComplete =
                data?['isProfileComplete'] as bool? ?? false;

            if (!hasVerifiedStudentIdentity) {
              if (isFreshmanProvisional) {
                return _buildProvisionalGate(
                  userData: data,
                  isProfileComplete: isProfileComplete,
                );
              }
              if (!hasUniversityIdentity) {
                return const ProfileSetupScreen();
              }
              return const OtpVerificationScreen();
            }

            if (isProfileComplete) {
              return const MainScreen();
            }

            return const ProfileSetupScreen();
          },
        );
      },
    );
  }
}
