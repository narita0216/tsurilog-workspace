# Harness Engineering — 作業ディレクトリ

釣りログのコードベース・開発フローを **AI 駆動開発(Claude Code)に適したもの** に変えていくプロジェクトの **作業領域** です。

Issue に書き切れない深さの分析・意思決定記録・継続的なナレッジをここに蓄積します。

---

## 何のためのディレクトリか

釣りログは **アプリ(`tsurilog-native`)と API(`tsurilog-backend`)が REST API でのみ結合**する 2 リポ構成。両者の唯一の契約面である **API コントラクト(エンドポイント・型・openapi)の整合性** を保つことが、AI 駆動開発を効かせる上での最大の鍵です。

ここでは:
- **コードベースの AI フレンドリー度を診断**(構造・規約・テスト・ドキュメント・コントラクト)
- **開発フローの診断**(Issue → ブランチ → PR → CI/EAS)
- **ハーネス基盤の整備**(`.mcp.json` / `.claude/` / スラッシュコマンド / サブエージェント / tools)
- **重要決定の記録(ADR)** と **継続的な発見の蓄積(findings)**
- **個別イニシアチブの推進**(API コントラクトカタログ、ローカル環境、テスト導入など)

---

## ディレクトリ構成

```
harness-engineering/
├── README.md                ← 本ファイル(オリエンテーション)
├── CHARTER.md               ← なぜやるか・スコープ・成功条件
├── ROADMAP.md               ← フェーズ計画
│
├── assessment/              ← 現状分析
│   ├── README.md
│   ├── codebase.md          ← コードベース AI フレンドリー診断
│   ├── workflow.md          ← 開発フロー診断
│   ├── tooling.md           ← Claude Code / MCP / ハーネス状況
│   └── effectiveness/       ← ハーネス使用ログ(events-<host>.jsonl)
│
├── decisions/               ← ADR(重要決定の記録)
│   ├── README.md / _template.md
│   ├── 0001-task-tracking.md
│   ├── 0002-api-contract-source-of-truth.md
│   ├── 0003-local-dev-environment.md
│   └── 0004-quality-gates-and-hooks.md
│
├── initiatives/             ← 進行中の個別イニシアチブ
│   ├── README.md / _template.md
│   ├── api-contract-catalog.md
│   └── local-dev-environment.md
│
├── findings/                ← 作業中に発見した事実・落とし穴(時系列)
│   ├── README.md
│   └── 2026-05-28-openapi-route-drift.md
│
└── tools/                   ← ハーネスツール(シェルスクリプト)
    ├── contract-check.sh    ← routes / native / openapi 3 点突合
    ├── php-lint.sh          ← PHP 8.4 構文 lint(PostToolUse hook)
    ├── backend-check.sh     ← Pint + PHPUnit(Docker)
    ├── native-check.sh      ← expo lint + tsc + Prettier
    ├── workspace-sync.sh    ← 2 リポの git 状態 pre-flight(SessionStart hook)
    └── effectiveness-log.sh ← ハーネス使用ログ JSONL 追記
```

---

## 大原則

### 動作検証・実装は **ローカル環境**で行う
- backend は **Docker Compose**(`api`/`queue`/`scheduler`/`db`)、native は **dev client**。本番・共有環境への直接接続で確認しない。
- ローカル構築・開発で判明した手順・暗黙ルール・ハマりどころは **都度 md を更新**:
  - 一般的な発見・落とし穴 → `findings/`(時系列メモ)
  - 定着した手順 → 各サブリポ `README.md` / `CLAUDE.md`
  - 定着した運用ルール → `decisions/`(ADR)

### API を触ったら 3 点を揃える
`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml` のいずれかを変えたら `/contract-check` で整合を確認する(ADR-0002)。

---

## 進め方

| 種類 | 置き場所 |
|---|---|
| 「やること」「TODO」「バグ」 | 各コードリポの GitHub Issue |
| 「なぜそう決めたか」(ADR) | `decisions/` |
| 「現状どうなっているか」(調査) | `assessment/` |
| 「進行中の取り組みの設計と進捗」 | `initiatives/<slug>.md` |
| 「気づき・落とし穴・参考情報」 | `findings/YYYY-MM-DD-<topic>.md` |

新しい決定: `cp decisions/_template.md decisions/000N-<slug>.md`
新しいイニシアチブ: `cp initiatives/_template.md initiatives/<slug>.md`

---

## 関連
- 横断 AI コンテキスト → `../CLAUDE.md`
- 横断アーキテクチャ → `../ARCHITECTURE.md`
- ハーネス共有設定 → `../.claude/README.md`

---

## このディレクトリのライフサイクル

ハーネス整備が一段落した後も、ここは **「ハーネスの取扱説明書 + 過去の意思決定の根拠集」** として残します。新規メンバーがここを読めばハーネスの設計意図が分かる状態を維持します。捨てない。
