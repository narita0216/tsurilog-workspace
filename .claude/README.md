# `.claude/` — 釣りログ Workspace ハーネス

`tsurilog-workspace/.claude/` は **Claude Code のハーネス設定**を集約するディレクトリです。個人秘密(API キー等)は含めず、コミット可能な共有部分のみ管理します。

---

## 構成

```
.claude/
├── README.md              ← 本ファイル
├── settings.json          ← 共有設定(hooks / permissions)
├── settings.local.json    ← 個人オーバーライド(gitignored)
├── SKILL_INDEX.md         ← Claude 用スキル索引
├── skill-template.md      ← 新規スラッシュコマンドの雛形
├── commands/              ← スラッシュコマンド
│   ├── contract-check.md  ← /contract-check   API 3 点ドリフト検査
│   ├── endpoint-trace.md  ← /endpoint-trace   1 エンドポイント横断追跡
│   ├── backend-check.md   ← /backend-check    Pint + PHPUnit(Docker)
│   ├── native-check.md    ← /native-check     expo lint + tsc + Prettier
│   └── ticket.md          ← /ticket           GitHub Issue 読込
└── agents/                ← サブエージェント
    ├── laravel-api-reviewer.md   ← Laravel 12 / PHP 8.4 レビュアー
    ├── expo-rn-reviewer.md       ← Expo / RN / TS レビュアー
    └── api-contract-checker.md   ← API コントラクト整合レビュアー
```

---

## 自動配線済みフック(settings.json)

### SessionStart
- **`workspace-sync.sh check`** — 起動時に native / backend の git 状態(ブランチ・未コミット)を通知。
- **`contract-check.sh --quiet`** — API コントラクトにドリフトがあれば 1 行で通知。無ければ無音。

### PostToolUse(Edit / Write / MultiEdit)
- **`php-lint.sh --hook`** — `tsurilog-backend/` 配下の `.php` を編集したら、Docker `php:8.4-cli` で `php -l`(構文チェック)。エラーなら exit 2 で AI を blocking。Docker 不在なら silent skip。native(TS)は対象外。

---

## permissions(deny)の意図

`settings.json` の `permissions.deny`(個人 `settings.local.json` でも上書き不可、安全側にマージ):

| deny | 理由 |
|---|---|
| `git push --force` / `-f` / `reset --hard` / `clean -f` / `branch -D` | 履歴・作業の破壊を防ぐ |
| `git push origin main|master` / `git checkout main|master` | 本番ブランチへの直接操作を防ぐ(PR 経由必須) |
| `migrate:fresh` / `migrate:reset` / `db:wipe` | **ローカル DB 全消去**を防ぐ(通常の `migrate` を使う) |
| `docker compose down -v` / `--volumes` | DB ボリューム破棄を防ぐ |
| `eas submit` | ストアへの誤提出を防ぐ(人間が明示実行) |
| `eas build` | 高コスト/長時間のビルドを誤発火させない(明示指示時のみ) |

deny に違和感がある場合は ADR を立ててチーム合意の上で外す運用にする。

---

## SETUP(各メンバー初回)

### 1. Docker と GitHub CLI

GitHub MCP は Docker で起動するため、ローカルに Docker が必要(Docker Desktop / OrbStack / colima いずれでも可)。`gh` も補助に推奨:

```bash
brew install gh        # まだなら
gh auth login
```

### 2. 環境変数(個人秘密)

`~/.zshrc` などに追加:

```bash
# GitHub MCP 用 PAT
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxxxxxxxxxx"
```

**必要 PAT スコープ:** native(`narita0216/tsurilog-native`)と backend(`reomin/tsurilog-backend`)**両方**にアクセスできること。

- Classic: `repo`(read/write) + `read:org`
- Fine-grained: 対象 repo に対し Contents / Issues / Pull requests を **Read and write**

> ⚠️ 2 リポの所有者が異なる(narita0216 / reomin)。Fine-grained PAT は両 org/owner の対象リポを含めて発行する。SAML SSO があれば token 設定で Authorize する。

シェルを再起動 or `source ~/.zshrc`。

### 3. 動作確認

```bash
cd ~/projects/turilog/tsurilog-workspace
claude

# 起動後
> /mcp                 # github が connected か
> /contract-check      # API 3 点チェックが動くか
> /ticket tsurilog-backend#1   # 任意の Issue 番号で
```

初回 `/mcp` 時に Docker image(`ghcr.io/github/github-mcp-server`)を pull するため少し時間がかかる。

---

## 個人オーバーライド

個人専用設定は `settings.local.json`(gitignored)に:

```json
{
  "model": "opus[1m]",
  "permissions": { "defaultMode": "auto" }
}
```

**マージ規則:** 個別 key は個人側優先 / `permissions.deny` `allow` は **マージ**(共有 deny を個人で外せない)。

---

## ファイルポリシー

| ファイル | git 管理 | 含めて良いもの |
|---|---|---|
| `settings.json` | ✅ commit | deny / allow / hooks 共通ルール |
| `settings.local.json` | ❌ gitignored | 個人モデル設定・個人 hooks |
| `.env` | ❌ gitignored | API キー等(基本は shell export 推奨) |
| `commands/*.md` / `agents/*.md` | ✅ commit | 共有スラッシュコマンド・サブエージェント |
| `cache/` / `tmp/` | ❌ gitignored | 一時ファイル |

---

## 関連
- ハーネスの意図 → `../CLAUDE.md` Section 8
- MCP 設定 → `../.mcp.json`
- スキル索引 → `SKILL_INDEX.md`
- ハーネス工学 → `../harness-engineering/README.md`
