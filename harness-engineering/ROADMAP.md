# Harness Engineering — Roadmap

最終更新: 2026-05-28

> CHARTER のスコープを **段階的に**実現する計画。フェーズの粒度はチームレビューで再調整可能。

---

## 現在地

**Phase 0(ハーネス基盤の立ち上げ)完了:**
- ✅ 横断 `CLAUDE.md` / `ARCHITECTURE.md` / `README.md` / `.gitignore`
- ✅ `.mcp.json`(GitHub MCP)
- ✅ `.claude/`(settings.json + hooks / README / SKILL_INDEX / skill-template)
- ✅ スラッシュコマンド 5 種(`contract-check` / `endpoint-trace` / `backend-check` / `native-check` / `ticket`)
- ✅ サブエージェント 3 種(`laravel-api-reviewer` / `expo-rn-reviewer` / `api-contract-checker`)
- ✅ ツール 6 種(`contract-check` / `php-lint` / `backend-check` / `native-check` / `workspace-sync` / `effectiveness-log`)
- ✅ ADR 0001–0004、initiatives 2 件、findings(openapi ドリフト)、assessment 3 件
- ✅ コントラクト検査が動作確認済み(ドリフト 16 件検出)

**重要前提:**
- 動作検証・実装はすべてローカル(backend Docker / native dev client)で行う。
- API を触ったら `/contract-check` で 3 点整合を確認する。

---

## Phase 1: 動かす(目安: 〜1 週間)

**目的:** メンバーがハーネス込みで実作業を開始できる状態。

| # | アクション | 担当 | 備考 |
|---|---|---|---|
| 1.1 | 各メンバー: `~/.zshrc` に `GITHUB_PERSONAL_ACCESS_TOKEN`(native/backend 両アクセス可) | 全員 | `.claude/README.md` |
| 1.2 | `/mcp` で github connected を確認 | 全員 | Docker 必要 |
| 1.3 | backend ローカル(Docker)起動 + `migrate --seed` 追試 | [TBD] | 手順を README に追記 |
| 1.4 | native dev client セットアップ追試(EAS) | [TBD] | 手順を README に追記 |
| 1.5 | スラッシュコマンド・サブエージェントの実運用ドッグフード | [TBD] | 1 週間 |
| 1.6 | ワークスペースを `git init` してハーネス資産を版管理(任意) | [TBD] | README 手順 |

**Exit 条件:** 全メンバーが `cd tsurilog-workspace && claude` でハーネスが効き、コマンドが実タスクで使われている。

---

## Phase 2: 見える化する(目安: 〜2 週間)

**目的:** アプリ ↔ API の契約・型・差分を見える形にする。

| # | アクション | 備考 |
|---|---|---|
| 2.1 | **API コントラクトカタログ**作成(エンドポイント別 3 点対応表) | `initiatives/api-contract-catalog.md` |
| 2.2 | openapi.yml を実ルートに同期(stale 3 件解消 + 未記載 13 件記載) | findings 2026-05-28 起点 |
| 2.3 | リクエスト/レスポンス型の native ↔ backend 突合(主要エンドポイント) | `api-contract-checker` 活用 |
| 2.4 | マスタ(魚種/釣法等)の native 利用箇所と ID ハードコード洗い出し | |

**Exit 条件:** 「このエンドポイントの契約は今どうなっているか」を AI に問えば即答できる。openapi が実装に追随。

---

## Phase 3: 守る(目安: 〜1 ヶ月)

**目的:** AI / 人間の変更を機械検証する層を厚くする。

| # | アクション | 備考 |
|---|---|---|
| 3.1 | backend critical path に PHPUnit テスト追加 | 認証・釣行 start/end・log 作成・公開制御 |
| 3.2 | `contract-check` を backend CI(GitHub Actions)にも組み込み | PR で自動検出 |
| 3.3 | native の型チェック(`tsc --noEmit`)を CI 化 | 現状 EAS ビルドのみ |
| 3.4 | PR テンプレに「/contract-check 実行済」「/backend-check or /native-check 済」チェック | 各リポ |

**Exit 条件:** コントラクトのドリフトと型/テスト退行が CI で検知される。

---

## Phase 4: 拡張する(目安: 〜四半期)

| # | アクション | 備考 |
|---|---|---|
| 4.1 | リクエスト/レスポンス型の機械突合ツール(現状はパスのみ) | contract-check を型レベルに拡張 |
| 4.2 | openapi → TS 型 / Laravel ルートの整合を生成ベースで検討 | スコープは ADR で判断 |
| 4.3 | サブエージェント追加(例: `migration-reviewer`) | |
| 4.4 | オンボーディング自動化スクリプト | 30 分以内 |

**Exit 条件:** CHARTER の KPI 達成。新規メンバーが 30 分で開発開始。

---

## 注記
- 各 Phase の Exit 条件を満たさず次へ進まない。
- スコープ拡大の誘惑は ADR で都度判断。
- ロードマップは生き物。少なくとも四半期に 1 回見直す。
