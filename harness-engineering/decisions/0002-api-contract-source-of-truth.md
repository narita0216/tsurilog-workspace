# ADR-0002: API コントラクトの真実は routes/api.php、3 点を揃える

- **Status:** Accepted
- **Date:** 2026-05-28
- **Deciders:** [TBD]
- **Tags:** harness, contract, core

## Context

釣りログはアプリ(`tsurilog-native`)と API(`tsurilog-backend`)が **REST API でのみ結合**する。両者を繋ぐ契約(エンドポイント・型・仕様)が **3 箇所に分散**している:

1. `tsurilog-backend/routes/api.php` — Laravel のルート定義
2. `tsurilog-native/api/**/*.ts` — アプリが叩くクライアント + 型
3. `tsurilog-backend/openapi.yml` — 仕様書

この 3 つはコードレビューだけでは静かにズレる。実際に 2026-05-28 計測で、openapi の `/analysis/env-data` `/analysis/scores` `/analysis/best-pattern` が実ルート(`/analysis/env_data` `/analysis/condition_stats` `/analysis/rate`)と一致せず、settings / notifications / push-devices など 13 ルートが openapi 未記載だった(`findings/2026-05-28-openapi-route-drift.md`)。

airtrunk の横断課題が「共有 DB・重複モデル」だったのに対し、釣りログの横断課題は **この API コントラクトのドリフト**である。ここを機械的に守ることがハーネスの中核価値。

## Options

### Option A: 真実を routes/api.php に固定し、3 点を手動で揃える + 機械検査
- **Pros:** 実装が常に真。低コストで始められる。検査ツール(`contract-check.sh`)で逸脱を即検出。
- **Cons:** 型レベルの整合は人/レビューに依存(ツールはパスのみ)。

### Option B: openapi.yml を真実(single source)にしてコード生成
- **Pros:** 1 ソースから native 型 / ルートを生成すれば理論上ズレない。
- **Cons:** 現 openapi が既にズレており信頼できない。生成基盤の導入コスト大。Laravel ルートの生成は非現実的。

### Option C: 何もしない
- ドリフトが増え続け、404・型不一致・仕様書不信が定着。

## Decision

**Option A を採用する。** **実装(`routes/api.php` とコントローラ)を契約の真実**とし、`openapi.yml` と native クライアントをそれに合わせる。API(これら 3 箇所のいずれか)を変更したら **`/contract-check` を必ず実行**し、新規エンドポイントは **3 箇所すべて**を同じ PR(または対の PR)で揃える。

将来、型レベルの自動突合や openapi 起点の生成は Phase 4 で再検討する(Option B への移行余地を残す)。

## Consequences
- **得るもの:** パスレベルのドリフトを機械検出。「どちらが真か」の判断が固定され AI が迷わない。
- **失うもの:** 型・レスポンス形の整合は当面レビュー依存(`api-contract-checker` サブエージェントで補う)。
- **新たに発生する作業:** API 変更時の 3 点更新 + `/contract-check`。SessionStart の `--quiet` 通知。
- **後戻り可能性:** reversible。

## Related
- ツール: `harness-engineering/tools/contract-check.sh`
- コマンド: `/contract-check` / `/endpoint-trace`
- サブエージェント: `api-contract-checker`
- findings: `2026-05-28-openapi-route-drift.md`
- initiative: `api-contract-catalog.md`
- CLAUDE.md §4 / §8.1
