// 公開リポジトリ用のプレースホルダーです。
//
// 本番の Firebase 設定を公開しないため、ここにはダミー値だけを入れています。
// 実際に開発する場合は、以下のコマンドで自分の Firebase プロジェクト用に
// 作り直してください。
//
//   flutterfire configure
//
// 本番値を含む Firebase 設定は、公開リポジトリにコミットしないでください。

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Linux 向けの Firebase 設定は未設定です。'
          '自分の Firebase プロジェクトで flutterfire configure を実行してください。',
        );
      default:
        throw UnsupportedError('未対応の Firebase プラットフォームです。');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'replace-with-your-web-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'your-firebase-project-id',
    authDomain: 'your-firebase-project-id.firebaseapp.com',
    storageBucket: 'your-firebase-project-id.appspot.com',
    measurementId: 'G-XXXXXXXXXX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'replace-with-your-android-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'your-firebase-project-id',
    storageBucket: 'your-firebase-project-id.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'replace-with-your-ios-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'your-firebase-project-id',
    storageBucket: 'your-firebase-project-id.appspot.com',
    iosBundleId: 'com.example.tekipa',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'replace-with-your-macos-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'your-firebase-project-id',
    storageBucket: 'your-firebase-project-id.appspot.com',
    iosBundleId: 'com.example.tekipa',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'replace-with-your-windows-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'your-firebase-project-id',
    authDomain: 'your-firebase-project-id.firebaseapp.com',
    storageBucket: 'your-firebase-project-id.appspot.com',
    measurementId: 'G-XXXXXXXXXX',
  );
}
