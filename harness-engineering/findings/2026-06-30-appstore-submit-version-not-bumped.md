# 2026-06-30 App Store 提出が突然失敗 = app.json の version を上げていなかった

## 症状
1.1.4 の中身を載せた main をビルドし `eas submit --platform ios` したら
`✖ Something went wrong when submitting your app to Apple App Store Connect.` で失敗。
今まで(過去リリース)は通っていたのに急に失敗した。

## 原因
- `app.json` の `version` が **`"1.1.3"` のまま**だった(release/1.1.3 → main で app.json は差分ゼロ＝1.1.4 で version を上げ忘れ)。
- `eas.json` は `appVersionSource: "remote"` + `autoIncrement: true`。これは **iOSビルド番号(CFBundleVersion)** を EAS が自動採番するだけで、**マーケティングバージョン(CFBundleShortVersionString)は app.json の `version` 由来**。
- 既に 1.1.3 が App Store Connect に存在するため、**同じ 1.1.3 のビルドを提出 → ASC が弾く** → submit が総称エラーで失敗。前回まで通っていた(=毎回新しいバージョンだった)とも整合。

## 切り分けのコツ
- `eas submit` の「Something went wrong …」は総称。**submission 詳細URL(expo.dev)に Apple 側の実エラー**が出る(例: version/bundle version already exists)。まずそれを見る。
- 「急に失敗」系は、コード/設定の**差分(`git diff <前リリース> <今>`)**を真っ先に見る。今回は app.json 差分ゼロ＝version 据え置きが即わかった。

## 恒久ルール(CLAUDE.md §6.1 に絶対ルールとして明記)
1. リリース対応は**最新 `develop` から `release/{version}` を作成**して行う。
2. **`app.json` の `version` は必ずそのブランチの `{version}` に更新**する(`appVersionSource: remote` でも必須)。

## 補足(同セッションの関連ミス)
- 緊急本番バグなのに最初 release/1.1.3 / develop 起点で hotfix を作り、**本番ブランチ=main 起点**にしていなかった。緊急 hotfix は main 起点 → main へPR → develop バックマージ。
- 外部SaaS(ASC/EAS)のUI・挙動は記憶で断定しない(§8.0.0)。submission ログの実文言で確定する。
