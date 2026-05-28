---
description: routes / native / openapi の 3 点 API コントラクトドリフトを検査する
argument-hint: "(任意) --strict で app→missing route があれば失敗扱い"
---

釣りログのアプリ(`tsurilog-native`)と API(`tsurilog-backend`)を繋ぐ唯一の面は HTTP エンドポイント。その定義は 3 箇所(`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml`)に分散し、静かにズレる。本コマンドは 3 点を機械突合してドリフトを報告する。背景は ADR-0002。

## 1. 実行

```bash
harness-engineering/tools/contract-check.sh $ARGUMENTS
```

- 引数なし: 全レポート(常に exit 0)
- `--strict`: アプリが叩くのに backend に該当ルートが無い(= 404 の実害)場合 exit 1

## 2. 出力の読み方

| 区分 | 意味 | 対応 |
|---|---|---|
| 🔴 アプリが叩くのに backend に無い | **実害(404)。最優先** | route を足すか、native の呼び出しを直す |
| 🟠 openapi にあるが実ルートに無い | stale な仕様書 | openapi.yml を実装に合わせる |
| 🟡 実ルートだが openapi 未記載 | ドキュメント不足 | openapi.yml に追記 |
| ⚪ backend にあるがアプリ未使用 | 参考情報 | `auth/*` 等は正常(トークン取得前で apiClient を経由しないため) |

## 3. ドリフトが見つかったら

- **API を追加/変更する作業の一部**なら、3 箇所(ルート定義・native クライアント・openapi)を同じ PR(または対の PR)で揃える。
- **既存の積み残し**なら、`harness-engineering/findings/` に日付ファイルで記録するか、対応 Issue を立てる。
- 型レベルの食い違い(リクエスト/レスポンスの形)はこのツールでは検出できない。疑わしければ `/endpoint-trace <name>` で個別に突き合わせる。

## 4. いつ呼ぶか
- `routes/api.php` / `tsurilog-native/api/**` / `openapi.yml` のいずれかを触ったら **必ず**(CLAUDE.md §8.1)
- SessionStart でも `--quiet` が自動実行され、ドリフトがあれば通知される

## 5. effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome contract-check
```
