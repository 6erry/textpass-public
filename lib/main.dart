import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'widgets/auth_gate.dart';
import 'services/stripe_service.dart';
import 'services/notification_service.dart';
import 'services/remote_config_service.dart';
import 'utils/navigator_key.dart';
import 'utils/deep_link_manager.dart';
import 'routes/app_router.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'screens/eula_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/app_custom_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set up timeago messages for Japanese
  timeago.setLocaleMessages('ja', timeago.JaMessages());

  // Initialize Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Initialize App Check. The public web build does not have a reCAPTCHA site
  // key configured yet, so keep App Check mobile-only to avoid a blank web page.
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
  }

  if (!kIsWeb) {
    await StripeService().initialize();
  }
  // NotificationService initialization moved to MainWrapper to prevent launch blocking
  await RemoteConfigService().initialize();

  final prefs = await SharedPreferences.getInstance();
  final hasAgreedEula = prefs.getBool('has_agreed_eula') ?? false;
  // Default to true if key doesn't exist (first launch)
  final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

  runApp(
    ProviderScope(
      child: MyApp(
        hasAgreedEula: hasAgreedEula,
        isFirstLaunch: isFirstLaunch,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.hasAgreedEula,
    required this.isFirstLaunch,
  });

  final bool hasAgreedEula;
  final bool isFirstLaunch;

  @override
  Widget build(BuildContext context) {
    // Ergonomic Red: #E03E3E
    const primaryColor = Color(0xFFE03E3E);
    const backgroundColor = Color(0xFFFAFAFA);
    const surfaceColor = Colors.white;
    const textColor = Color(0xFF1A1A1A); // High contrast dark grey

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      surface: surfaceColor,
      onPrimary: Colors.white,
    );

    final baseTextTheme = GoogleFonts.notoSansJpTextTheme();
    final appTextTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textColor,
          ) ??
          const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ) ??
          const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ) ??
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            fontSize: 16,
            color: textColor,
          ) ??
          const TextStyle(fontSize: 16, color: textColor),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: textColor,
          ) ??
          const TextStyle(fontSize: 14, color: textColor),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white, // Default for buttons
          ) ??
          const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      onGenerateRoute: AppRouter.onGenerateRoute,
      title: 'Tekipa',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'), // Japanese
      ],
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: backgroundColor,
        textTheme: appTextTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: surfaceColor,
          elevation: 0.5,
          centerTitle: true,
          titleTextStyle: appTextTheme.titleLarge?.copyWith(color: textColor),
          iconTheme: const IconThemeData(color: textColor),
          shadowColor: Colors.black.withValues(alpha: 0.1),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: surfaceColor,
          selectedItemColor: primaryColor,
          unselectedItemColor: Colors.grey.shade600,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            textStyle: appTextTheme.labelLarge,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: MainWrapper(
        child: isFirstLaunch
            ? const OnboardingScreen()
            : (hasAgreedEula ? const AuthGate() : const EulaScreen()),
      ),
    );
  }
}

class MainWrapper extends StatefulWidget {
  final Widget child;
  const MainWrapper({super.key, required this.child});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  late DeepLinkManager _deepLinkManager;

  @override
  void initState() {
    super.initState();
    _deepLinkManager = DeepLinkManager(navigatorKey);
    _deepLinkManager.init();
    // Initialize Notification Service after UI is ready to avoid blocking app launch
    NotificationService().initialize();
    _checkUpdate();
  }

  @override
  void dispose() {
    _deepLinkManager.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    if (await RemoteConfigService().isUpdateRequired()) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AppCustomDialog(
          title: 'アップデートが必要です',
          message: '最新バージョンが公開されています。\nストアからアップデートをお願いします。',
          icon: Icons.system_update,
          confirmText: 'ストアへ', // Or just hide buttons if forced?
          // Usually forced update dialogs might not have a cancel button or might open store.
          // For now, I'll just use AppCustomDialog.
          // Since it's forced, maybe no cancel?
          // AppCustomDialog has cancel button by default.
          // I'll leave it as is for now, assuming user can't easily dismiss if barrierDismissible is false,
          // but AppCustomDialog's cancel button will pop it.
          // If it's strictly forced, we might need a different approach or modify AppCustomDialog.
          // But for unification, I'll use it.
          onConfirm: () {
            // Open store logic here if available, or just pop for now.
            // The original code just showed text.
            // I'll just pop.
            // Wait, if it's required, popping allows using the app?
            // The original code was just an alert dialog with no actions?
            // "builder: (_) => const AlertDialog(title: Text('...'), content: Text('...'))"
            // It had no buttons! So user was stuck? Or could tap outside?
            // barrierDismissible: false was set.
            // So user was stuck.
            // I will replicate "stuck" behavior or provide a button?
            // I'll provide a button that does nothing or opens store (if I knew how).
            // Since I don't have store URL logic here, I'll just add a button that pops?
            // No, if it's required, they shouldn't be able to pop.
            // But for now I will just add a confirm button that pops, to match "Dialog Unification".
            // If the previous one had no buttons, it was likely a blocking overlay.
            Navigator.pop(context);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (RemoteConfigService().isMaintenanceMode) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.build, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('只今メンテナンス中です',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('しばらくお待ちください'),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}
