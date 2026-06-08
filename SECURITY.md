# セキュリティ方針

このリポジトリは、実績公開・開発参考用のサニタイズ済み公開版です。

本番環境の認証情報、Firebase プロジェクト設定、Stripe シークレット、サービスアカウントキー、ローカル環境変数、実運用データは含めていません。

以下は絶対にコミットしないでください。

- Firebase Admin SDK のサービスアカウント JSON
- `.env` や `functions/.env.*`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- 本番値を含む `lib/firebase_options.dart`
- Stripe の secret key / webhook secret
- 実ユーザーの個人情報、取引情報、決済 ID
- Firestore / Storage からエクスポートした実データ

もし秘密情報を誤ってコミットした場合は、Git から消すだけでは不十分です。必ず各サービスの管理画面で該当キーを削除・再発行してください。
