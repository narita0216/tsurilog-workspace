# Skill Index — Claude 用

このファイルは **Claude が「どの skill を呼ぶべきか」判定する時の検索インデックス**です。人間用ドキュメントではなく、`.claude/commands/` 全 skill の意図を一望する索引として機能します。

> **使い方:** 依頼を受けたら自然文で skill のマッチを判断し、迷ったら下の `Trigger` 列を grep する。

---

## 索引

| skill | 主目的 | Trigger キーワード | 入力 | 出力 |
|---|---|---|---|---|
| `/contract-check [--strict]` | routes / native / openapi の 3 点ドリフト検査 | "API 整合", "コントラクト", "openapi ずれ", "エンドポイント追加した", "404 する" | (なし) | ドリフト一覧 + 件数 |
| `/endpoint-trace <name>` | 1 エンドポイントを両リポ横断で追跡(route / controller / request / client / 型) | "このエンドポイントどこ", "/logs 追って", "API の実装と呼び出し", "横断で見たい" | エンドポイント名/パス | route + controller + native client + 型の対応 |
| `/backend-check [pint\|test]` | Laravel Pint + PHPUnit を Docker(`api` コンテナ)で実行 | "backend テスト", "Pint", "PHP の整形", "PR 前チェック(API)" | 任意 | pass/fail + ログ |
| `/native-check [types\|format]` | `expo lint` + `tsc --noEmit`(+ Prettier) | "native lint", "型チェック", "tsc", "Prettier", "PR 前チェック(アプリ)" | 任意 | pass/fail + ログ |
| `/native-qa [run\|install\|check]` | dev-client をシミュレータで動かし画面遷移→スクショ撮影(実質E2E)。build要否は指紋で自動判定し EAS 無料枠を温存 | "動作確認", "スクショ", "UIチェック", "画面の証跡", "E2E", "dev-client で確認", "PR にスクショ" | (任意) flow パス | スクショ PNG + build要否判定 |
| `/ticket <repo#n>` | GitHub Issue を読み込んで作業準備 | "issue#N", "あの件", "チケットやって", "続きやって" | `<repo>#<n>` | Issue 要約 + 関連ファイル + 提案ブランチ |

---

## 判定フロー(Claude 用)

1. **ユーザーが明示的に `/<skill>` を叩いた** → そのまま実行
2. **API を触る依頼(routes / native api / openapi の追加・変更)** → 作業後に `/contract-check` 必須(ADR-0002)
3. **特定エンドポイントの調査** → `/endpoint-trace <name>`
4. **PR 直前** → backend を触ったら `/backend-check`、native を触ったら `/native-check`。**native の UI/画面を変えたら `/native-qa`** でシミュレータ動作確認 + スクショを PR 添付(型・lint が通る ≠ 画面が正しい)
5. **既存 Issue の再開** → `/ticket <repo>#<n>`
6. **横断レビューが要る大きめ変更** → サブエージェント(`laravel-api-reviewer` / `expo-rn-reviewer` / `api-contract-checker`)に投げる

---

## skill を追加するときの作法

新しい skill を `.claude/commands/<kebab-name>.md` に追加したら、**本ファイルに 1 行追記**する(無いと将来の Claude が見落とす)。

**雛形を使うこと:** `.claude/skill-template.md` をコピー。テンプレには「末尾で `effectiveness-log.sh emit` 必須」「`commands/` 配下に置く」が組み込まれている。

> ⚠️ この index ファイル自体は `.claude/commands/` 配下に置かない(置くと slash command 化する)。`.claude/` 直下に。

### 必須要件(skill 末尾の emit)

新規 skill は末尾に以下を入れる(死蔵検出のため):

```bash
harness-engineering/tools/effectiveness-log.sh emit \
  --source skill --event invoke --outcome <skill-name>
```

Claude Code には skill 起動 hook が無いため、skill 自身で emit しないと使用統計が取れない。
