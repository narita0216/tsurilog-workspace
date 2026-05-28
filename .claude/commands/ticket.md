---
description: GitHub Issue を読み込んで横断作業の準備をする
argument-hint: "<repo>#<n>  例: tsurilog-backend#12  tsurilog-native#5"
---

`$ARGUMENTS` で指定された GitHub Issue を読み込み、釣りログの横断コンテキストで作業を開始できる状態にしてください。

## 0. 対象リポの判定

引数の形式:
- `tsurilog-backend#<n>` → `reomin/tsurilog-backend`
- `tsurilog-native#<n>` → `narita0216/tsurilog-native`
- 番号のみ → どちらの Issue か確認(曖昧なら聞く)

## 1. Issue を取得

**第一選択: GitHub MCP**

```
mcp__github__issue_read / get_issue で owner/repo/issue_number を指定して本文・コメントを取得
```

MCP が使えない場合のフォールバック:

```bash
gh issue view <n> --repo <owner>/<repo> --comments
```

## 2. 関連ファイルを横断 grep

Issue の本文からキーワード(エンドポイント名・機能名・モデル名)を拾い、両リポで関連箇所を探す:

```bash
rg -ln "<keyword>" tsurilog-backend/app tsurilog-backend/routes
rg -ln "<keyword>" tsurilog-native/api tsurilog-native/hooks tsurilog-native/app
```

API に関わる Issue なら `/endpoint-trace <keyword>` で全体像を取る。

## 3. 着手準備の提示

以下をまとめて報告:

```
🎫 <repo>#<n>: <タイトル>

📋 要約
  - <Issue の要点を 2-3 行>

📂 影響範囲(grep 結果)
  - backend: <files>
  - native : <files>

🌿 提案ブランチ
  - 対象リポ: <tsurilog-backend or tsurilog-native>
  - develop 起点で: feature/issue-<n>-<slug>

✅ 完了条件(推定)
  - <Issue から読み取れる done の定義>
  - API を触るなら /contract-check、PR 前に /backend-check or /native-check
```

## 4. 注意
- ブランチは **対象コードリポの最新 `develop` から**切る(`main` 起点にしない)。
- 作業はそのコードリポ内で行い、PR は `develop` 宛て。
- 横断調査ログ・発見は `harness-engineering/findings/` に残してよい。

## 5. effectiveness emit

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome ticket \
  --details '{"ref":"<arg>"}'
```
