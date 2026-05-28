# Initiative: API コントラクトカタログ

- **Status:** 🟡 進行中
- **Owner:** [TBD]
- **Date started:** 2026-05-28
- **Related:** ADR-0002 / findings/2026-05-28-openapi-route-drift.md

## なぜやるか(目的)

アプリ ↔ API の契約が 3 箇所(`routes/api.php` / `tsurilog-native/api/**` / `openapi.yml`)に分散し、既にドリフトしている。エンドポイント単位で **「どこに何があり、型は一致しているか」を一望できる表** があれば、AI も人間も変更の影響範囲と整合を即判断できる。`contract-check.sh` はパスの有無を見るが、型・レスポンス形までは見ない。その差を埋める。

## ゴール / 完了条件

- [ ] 全 35 エンドポイントについて、route / controller / request / native client / 型 / openapi の対応表を作る
- [ ] openapi の stale 3 件(`/analysis/env-data` `/analysis/scores` `/analysis/best-pattern`)を実ルートに修正
- [ ] openapi 未記載 13 件を記載
- [ ] 主要エンドポイント(records / logs / analysis / settings)のリクエスト/レスポンス型が native ↔ backend で一致していることを確認
- [ ] `contract-check.sh` の出力が「app→missing 0 / openapi stale 0」になる

## 進め方(計画)

1. `contract-check.sh` の現状出力を基準にする(下記スナップショット)。
2. エンドポイントごとに `/endpoint-trace <name>` で route/controller/client/型を集め、表に落とす。
3. openapi.yml を実装(routes + controller のレスポンス)に合わせて更新。
4. 型の不一致は `api-contract-checker` サブエージェントで洗い、native か backend を真に合わせる(基本は backend が真)。

## 進捗ログ

- **2026-05-28:** `contract-check.sh` を新設し初回計測。ドリフト 16 件(app→missing 0 / openapi stale 3 / 未記載 13)。詳細は findings 参照。カタログ本体はこれから。

## カタログ(雛形 — 埋めていく)

| エンドポイント | route | controller | request | native client | 型一致 | openapi |
|---|---|---|---|---|---|---|
| POST /logs | ✅ | LogCreateController | [TBD] | api/log/create.ts | [TBD] | ❌ 未記載 |
| GET /analysis/rate | ✅ | GetAnalysisRateController | — | api/analysis/get-rate.ts | [TBD] | ❌(openapi は `/analysis/scores`?) |
| ... | | | | | | |

## 落とし穴・メモ

- native は `/api` プレフィックス付き、routes は無し。比較時に正規化する(`contract-check.sh` 実装済)。
- `auth/apple` `auth/google` は native では `apiClient` 非経由(トークン取得前)。「アプリ未使用」と出るが正常。
