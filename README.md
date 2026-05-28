# 釣りログ Workspace

釣りログ(https://tsuri-log.com/)の **アプリ(`tsurilog-native`)と API(`tsurilog-backend`)を横断的に**扱うための作業ディレクトリです。AI 駆動開発(Claude Code)で両リポにまたがる作業を行う起点になります。

---

## このディレクトリの目的

- 横断アーキテクチャ・規約・運用知見の共有(`CLAUDE.md` / `ARCHITECTURE.md`)
- **API コントラクト(アプリ ↔ API のエンドポイント契約)の整合性**を機械的に監視
- ハーネス(Claude Code 設定・スラッシュコマンド・サブエージェント・ツール)の集約

このディレクトリ自体に**アプリ/API のコードは含みません**。各コードはそれぞれの個別リポジトリで管理されます。

---

## ディレクトリ構成

```
tsurilog-workspace/
├── CLAUDE.md                 ← 横断 AI コンテキスト
├── ARCHITECTURE.md           ← 横断アーキテクチャ
├── README.md                 ← 本ファイル
├── .gitignore                ← サブリポ・秘密を除外
├── .mcp.json                 ← GitHub MCP 設定
├── .claude/                  ← ハーネス設定(settings / commands / agents / SKILL_INDEX)
├── harness-engineering/      ← 分析・ADR・initiatives・findings・tools
├── tsurilog-native/          ← アプリ(別リポ / gitignored)
└── tsurilog-backend/         ← API(別リポ / gitignored)
```

---

## セットアップ(新規メンバー)

```bash
# 1. ワークスペースを用意(本ハーネス資産を配置する親ディレクトリ)
cd ~/projects/turilog/tsurilog-workspace

# 2. サブリポジトリを兄弟として clone
git clone git@github-narita0216:narita0216/tsurilog-native.git
git clone https://github.com/reomin/tsurilog-backend.git

# 3. backend のローカル環境(Docker)
cd tsurilog-backend
cp .env.example .env            # DB を pgsql / 5432 / tsurilog に合わせる(下記参照)
docker compose up -d --build
docker compose exec api composer install
docker compose exec api php artisan key:generate
docker compose exec api php artisan migrate --seed
cd ..

# 4. native のローカル環境
cd tsurilog-native
npm install
cp .env.example .env 2>/dev/null || true   # EXPO_PUBLIC_API_DOMAIN 等を設定
# 開発ビルド(dev client)を実機/シミュレータに導入後:
npx expo start --dev-client
cd ..
```

> backend の `.env` は `DB_CONNECTION=pgsql` / `DB_HOST=db`(compose 内)/ `DB_DATABASE=tsurilog` / `DB_USERNAME=tsurilog_user` に合わせる。詳細は `tsurilog-backend/README.md`。

### ハーネスのメタリポジトリ

このワークスペース親は **git 管理下のメタリポジトリ**です(ハーネス資産を版管理)。

- remote: `git@github-narita0216:narita0216/tsurilog-workspace.git`
- ブランチ: `master`(workspace の唯一の作業ブランチ)
- サブリポ(`tsurilog-native` / `tsurilog-backend`)・秘密情報は `.gitignore` で除外

**`master` は AI(Claude)が直接 commit / push してよい** AI 管理ブランチです。Stop フック(`harness-autosave.sh`)が、ハーネス/ドキュメントの変更をターン終了時に自動 commit & push します(ADR-0005)。無効化したい時は `HARNESS_AUTOSAVE_DISABLE=1`。

> **注:** Claude のメモリ(`~/.claude*/.../memory/`)はこのリポの外にあり push されません。共有したい学びは `harness-engineering/findings/` か `CLAUDE.md` に書き出します(CLAUDE.md §8.5)。

---

## AI 駆動開発の使い方

### 横断作業

```bash
cd ~/projects/turilog/tsurilog-workspace
claude
```

`CLAUDE.md` が自動で読まれ、両リポにまたがるコンテキストで作業できます。

### よく使うスラッシュコマンド

| コマンド | 用途 |
|---|---|
| `/contract-check` | routes / native / openapi の 3 点ドリフト検査(**API を触ったら必須**) |
| `/endpoint-trace <name>` | 1 エンドポイントを両リポ横断で追跡(route / controller / client / 型) |
| `/backend-check` | Laravel Pint(`--test`)+ PHPUnit を Docker で実行 |
| `/native-check` | `expo lint` + `tsc --noEmit`(+ Prettier) |
| `/ticket <repo#n>` | GitHub Issue を読み込んで作業準備 |

詳細は `.claude/SKILL_INDEX.md`。

### 単一リポの作業

```bash
cd tsurilog-backend   # または tsurilog-native
claude
```

---

## 横断ドキュメントの編集ルール

- **`CLAUDE.md`** は AI への指示を含む。ルール変更はチーム合意の上で。
- **`ARCHITECTURE.md`** は事実ベース。発見・確認した情報を蓄積。
- サブリポ固有の情報はここではなく各リポの `CLAUDE.md` / README に書く。

---

## 関連リソース

- 横断 AI コンテキスト → `CLAUDE.md`
- 横断アーキテクチャ → `ARCHITECTURE.md`
- ハーネス設定 → `.claude/README.md`
- ハーネス工学(分析・ADR)→ `harness-engineering/README.md`
- サービスサイト → https://tsuri-log.com/
