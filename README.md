# Tekipa / TextPass

Tekipa は、大学生向けのキャンパスプラットフォームアプリです。

このリポジトリは、実績公開・開発参考用に用意したサニタイズ済みの公開版です。本番環境の秘密情報、Firebase プロジェクト設定、Stripe シークレット、サービスアカウントキー、実運用データ、非公開リポジトリの Git 履歴は含めていません。

## 主な機能

- 教科書・授業関連品の出品、購入
- Stripe Connect を使った現物商品の決済
- 同じ出品者の商品をまとめて相談できるまとめ買い機能
- 時間割管理、シラバス検索
- 年度をまたいで参照できる授業レビュー
- サークル、イベント情報
- 取引チャット、受け渡し Todo、QR 完了、ユーザーレビュー
- 通報、モデレーション、管理者向け監査ログ
- Firebase Auth / Firestore / Storage / Functions / Messaging / Remote Config / Crashlytics / App Check 連携

## 技術スタック

- Flutter / Dart
- Firebase Auth, Firestore, Storage, Cloud Functions, Messaging, Remote Config, Crashlytics, App Check
- Stripe Connect Express + PaymentSheet
- Cloud Functions: TypeScript / Node.js 22

## ローカルセットアップ

```sh
flutter pub get
npm --prefix functions install
```

この公開版には、本番値を含まないダミーの `lib/firebase_options.dart` を置いています。実際に動かす場合は、自分の Firebase プロジェクトで設定を作り直してください。

```sh
flutterfire configure
```

実開発では、以下のファイルをローカルに配置します。ただし、公開リポジトリにはコミットしないでください。

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

## Cloud Functions

Stripe などの秘密情報は、自分の Firebase プロジェクト側に設定してください。

```sh
firebase functions:secrets:set STRIPE_SECRET_KEY
```

ローカル環境変数の例は `functions/.env.example` にあります。本物の `.env` ファイルは Git 管理対象外です。

よく使う確認コマンド:

```sh
flutter analyze
npm --prefix functions run build
```

デプロイは、Firebase 設定を済ませた非公開の開発環境から行ってください。

```sh
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
```

## データ構造の概要

- `users/{uid}`: ユーザー、大学 ID、通知、Stripe、時間割設定
- `books/{bookId}`: 教科書・授業関連品の出品
- `bundle_requests/{bundleRequestId}`: まとめ買い依頼
- `purchase_holds/{holdId}`: サーバー管理の購入中ロック
- `chat_rooms/{chatId}`: 取引とチャット
- `circles/{circleId}` / `events/{eventId}`: サークルとイベント
- `syllabus_master/{id}` / `class_reviews/{id}`: シラバスと授業レビュー
- `reviews/{id}`: 取引レビュー
- `reports/{id}` / `announcements/{id}`: 通報と運営お知らせ

## 公開用リポジトリとしての注意

公開前・公開後の確認には、以下のファイルを使ってください。

- `SECURITY.md`
- `PUBLIC_RELEASE_CHECKLIST.md`

元の非公開リポジトリの履歴に本番キーが含まれていた可能性がある場合は、公開版を作るだけでなく、Firebase / Stripe など各サービス側でキーを削除・再発行してください。この公開版には非公開 Git 履歴を持ち込んでいません。
