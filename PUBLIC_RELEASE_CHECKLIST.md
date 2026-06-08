# 公開前チェックリスト

このリポジトリを公開する前に、以下を確認してください。

- [ ] 非公開リポジトリの `.git` 履歴を持ち込んでいない
- [ ] `serviceAccountKey.json` が存在しない
- [ ] `.env` や `functions/.env.*` が存在しない
- [ ] 本番の Firebase 設定ファイルが存在しない
- [ ] Stripe の secret key / webhook secret が存在しない
- [ ] 実ユーザーのデータや Firestore エクスポートが存在しない
- [ ] スクリーンショットやサンプルデータに個人情報が映っていない
- [ ] `flutter analyze` が通る
- [ ] `npm --prefix functions run build` が通る

推奨する確認コマンド:

```sh
find . -name 'serviceAccountKey.json' -o -name '.env*' -o -name 'google-services.json' -o -name 'GoogleService-Info.plist'
rg -n "PRIVATE KEY|sk_live|sk_test|whsec_|serviceAccountKey|ELMS_PASSWORD|password"
flutter analyze
npm --prefix functions run build
```
