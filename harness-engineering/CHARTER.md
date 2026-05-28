# Harness Engineering — Project Charter

> **このドキュメントはチームでのレビュー・合意を経て確定させる初稿です。** 仮置きは `[TBD]` で示します。

---

## 1. 問題提起

釣りログは **アプリ(`tsurilog-native`)と API(`tsurilog-backend`)** の 2 リポ構成で、両者は REST API でのみ結合する。現状、AI 駆動開発(Claude Code)を効果的に使うには次の障害がある。

### 観察される症状
- **API コントラクトが 3 箇所に分散して静かにズレる**(`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml`)。実際に openapi の `/analysis/*` が実ルートと一致せず、13 ルートが未記載(2026-05-28 計測 → findings)。
- AI に「アプリ側とAPI側のどちらが真か」を毎回説明する必要がある(横断ルールの不在)。
- テストが薄い(backend は Feature/Unit 少、native は実質なし)→ AI 変更の安全性検証が手動頼み。
- 横断的な品質ゲート(lint / 型 / コントラクト)が機械化されておらず、AI のアウトプットを機械検証できない。
- ローカル環境(backend Docker / native dev client)の暗黙手順が共有されていない。

### 影響
- アプリと API の片側だけ修正して **404・型不一致** を生む事故リスク。
- openapi を信じた実装が古い仕様を参照する。
- AI 活用の価値が顕在化しない(前提共有に時間が溶ける)。

---

## 2. ビジョン(理想状態)

> 釣りログの開発作業で、Claude Code が **設計議論から実装・レビュー・PR まで** 生産性を加速し、**アプリと API の契約が常に整合**している状態。

実現したい体験:
- メンバーが Issue を立てると、AI が横断ルール(コントラクトの真実は routes/api.php、native と openapi をそれに合わせる)を理解した上で着手できる。
- API を触ると **AI が自動でコントラクトのズレを検出・指摘**する。
- AI のアウトプットが lint・型・テスト・コントラクト検査・横断レビュー(サブエージェント)で機械検証される。
- 新規メンバーが **30 分以内に** ハーネス込みで開発開始できる。

---

## 3. スコープ

### 3.1 In-Scope(やる)
- ✅ workspace 横断ハーネス(`.mcp.json` / `.claude/`)整備
- ✅ 横断 `CLAUDE.md` / `ARCHITECTURE.md` 整備
- ✅ スラッシュコマンド(`/contract-check` `/endpoint-trace` `/backend-check` `/native-check` `/ticket`)
- ✅ サブエージェント(`laravel-api-reviewer` `expo-rn-reviewer` `api-contract-checker`)
- ✅ コントラクト機械検査ツール(`contract-check.sh`)+ SessionStart 通知
- ✅ 品質ゲート(PHP 8.4 lint hook / Pint / PHPUnit / expo lint / tsc)
- **API コントラクトカタログ化**(エンドポイント別の 3 点対応表)
- **ローカル環境(backend Docker / native dev client)のセットアップとドキュメント化**
- 自動テストの最小ライン(critical path)

### 3.2 Out-of-Scope(やらない)
- ❌ 機能要件の追加・改廃(本プロジェクトは開発基盤側のみ)
- ❌ アーキテクチャの大規模再設計(別 API 設計への移行等)
- ❌ インフラ移行(Apache+Docker → 別基盤など)
- ❌ openapi からのコード自動生成への全面移行(将来検討。まずは手動整合 + 機械検査)

---

## 4. 成功条件(KPI)

> **初期案。チームレビューで確定。**

### 4.1 定量
| 指標 | 現状 | 目標 |
|---|---|---|
| 横断 `CLAUDE.md` 整備 | 0 → 1 | ✅ |
| スラッシュコマンド数 | 0 | 5 以上 ✅ |
| サブエージェント数 | 0 | 3 以上 ✅ |
| API コントラクトのドリフト件数 | 16(2026-05-28) | openapi stale 0 を維持、未記載を段階的に解消 |
| backend critical path テスト | [TBD] | 認証・釣行 start/end・log 作成を最低カバー |
| 新規メンバーオンボーディング | [TBD] | 30 分以内 |

### 4.2 定性
- 「AI 出力をそのまま PR に通せる」率の向上
- 片側修正起因の 404 / 型不一致バグの減少

---

## 5. ステークホルダー

> **[TBD] チームで確認・更新**

- **オーナー:** [TBD]
- **ドライバー:** [TBD]
- **リポジトリ所有:** native = `narita0216` / backend = `reomin`(権限分断に注意)
- **意思決定:** ADR ベースで合議

---

## 6. 制約・前提
- 既存リリースサイクル(EAS ビルド / backend CI)を止めない。
- 個人秘密(PAT・API キー・`.p8` 等)はリポにコミットしない。
- `main` 直 push 禁止 / PR 経由のルールを本プロジェクトでも遵守。
- ローカル DB 破壊操作(`migrate:fresh` / `db:wipe` / `down -v`)を AI に許さない(deny 済み)。

---

## 7. リスク

| # | リスク | 緩和策 |
|---|---|---|
| 1 | スコープ拡大(コード自動生成まで含めたくなる) | スコープ外を明記、ADR で都度判断 |
| 2 | AI 過信で片側だけ修正 | `/contract-check` + `api-contract-checker` で機械/レビュー二段 |
| 3 | 2 リポの所有者分断で PR フローが詰まる | PAT スコープを両 owner に通す、運用を `.claude/README.md` に明記 |
| 4 | 品質ゲートが既存 CI を壊す | hook / tools は独立。既存 GitHub Actions に干渉しない |

---

## 8. 進捗の見える化
- 各イニシアチブは `initiatives/<slug>.md` で計画 + 進捗を管理
- 主要決定は `decisions/000N-*.md`
- ハーネス使用状況は `assessment/effectiveness/events-*.jsonl`(自動蓄積)
- 全体ロードマップは `ROADMAP.md`
