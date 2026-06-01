# AI戦略機能 — 実装タスク分解(GitHub Issue 下書き兼タスクボード)

`initiatives/ai-strategy-feature.md` の実装タスク。GitHub Issue が使えない間はここを正本のタスクボードとする
(各タスクはそのまま Issue 本文に転記できる粒度)。ADR-0006 / 0007 準拠。

- **Status 凡例:** 🔵未着手 / 🟡進行中 / 🟢完了 / ⛔ブロック
- **対象リポ:** BE=tsurilog-backend / NA=tsurilog-native

---

## Phase 1: 既存環境データの WWO 廃止 → Open-Meteo + tide736.net + 海しる(ADR-0007)

> 既存分析が依存するため**段階的 + Feature テスト必須**。`develop` 起点 `feature/env-data-open-meteo`。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| BE-1 | BE | 環境データソースのクライアント追加(Open-Meteo forecast/marine/archive、tide736 潮位、海しる地形)。設定は `config/`、キーは `.env`(デフォルト値に書かない・ADR-0006) | 各 API を叩いて生値を取得できる単体確認 | 🔵 |
| BE-2 | BE | `GetEnvData` 書き換え: 天気/風/気温=Open-Meteo forecast、波/水温=Open-Meteo marine、潮位=tide736。WWO 呼び出しを除去 | 既存 `index()` シグネチャ維持で EnvCache を生成 | 🔵 |
| BE-3 | BE | マッピング再実装: **WMO 天気コード**→`weathers`(新 `convertWmoCodeToWeatherId`)、風 m/s バケット(`windspeed_unit=ms`)、波高 m バケットは既存閾値流用 | 既存マスタID体系と整合(分析が壊れない) | 🔵 |
| BE-4 | BE | 潮の動き(`calculateTideAction`)を tide736 の満潮(flood)/干潮(edd)イベントで動くよう改修。**lat/lng→最寄り港(pc/hc)の解決**が必要(現状は固定 pc=28,hc=9)。港リスト or 海しる潮汐推算(点指定)を検討 | 任意地点で上げ/下げ3分7分/満干が算出できる | 🔵 |
| BE-5 | BE | `EnvCache` に**生値カラム追加**(波高m・風速m/s・潮位cm 等、additive migration)+ forecast メタ(`fetched_at`/`is_forecast`)。既存バケット列は分析互換のため維持 | migrate 追記式・既存列を壊さない | 🔵 |
| BE-6 | BE | **キャッシュ失効(TTL)**: forecast 行は対象日が近づいたら再取得(古い予報を使わない)。潮は決定論的で対象外 | 1週間前予報が当日まで残らない | 🔵 |
| BE-7 | BE | 海しる(MSIL)で**水深/海底地形**を取得・キャッシュする新サービス + 利用登録 + クレジット表記 | 地点の水深/地形が取得できる | 🔵 |
| BE-8 | BE | Feature テスト: `GetAnalysis*`(env_data/condition_stats/rate)+ `GetEnvData` のマッピング(HTTP モック)。移行前後で分析結果が一致 | テスト green(`/backend-check`) | 🔵 |
| BE-9 | BE | WWO 設定/コード除去 + キーのデフォルト値削除 + ローテーション。env-data レスポンス形が変われば `/contract-check` + openapi 更新 | WWO 参照ゼロ・contract green | 🔵 |

## Phase 2: AI戦略 backend(ADR-0006)

> `develop` 起点 `feature/ai-strategy-api`。1 EP=1 コントローラ / Request / `*ResponseService`(§8.2)。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| BE-10 | BE | DB: `ai_strategies`(事前/現地・入力・結果)、会話履歴、利用回数のマイグレーション | migrate 追記式 | 🔵 |
| BE-11 | BE | Claude 連携(Sonnet/Haiku 振り分け + Prompt Caching)HTTP クライアント。キーは `.env` | 戦略テキストが生成できる | 🔵 |
| BE-12 | BE | Gemini 動画解析連携(File API アップロード→解析→Claude へ受け渡し) | 動画から状況要約が返る | 🔵 |
| BE-13 | BE | 情報収集の組み立て(新 env/tide/海しる + 自分/他者の過去釣行 + 釣果率)→ プロンプト | 必要データが揃ってプロンプト生成 | 🔵 |
| BE-14 | BE | エンドポイント: 事前戦略作成 / 現地戦略作成 / 履歴取得(各 1 コントローラ)。`is_success` 慣習・直近5往復 | 3 点コントラクト整合(`/contract-check`) | 🔵 |
| BE-15 | BE | 利用制限(無料3/日・プレミアム10/日)+ 会話履歴保存 | 制限超過で適切に拒否 | 🔵 |
| BE-16 | BE | openapi.yml 追記 + `/contract-check` green | ドリフトなし | 🔵 |

## Phase 3: native 実接続

> `develop` 起点 `feature/ai-strategy-api-integration`。モック(`feature/ai-strategy-mock`)を実 API に差し替え。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| NA-1 | NA | `api/ai-strategy/*`(1リクエスト1ファイル + 型)+ `hooks/use-ai-strategy.ts`(TanStack Query) | 型が backend と一致 | 🔵 |
| NA-2 | NA | モックの `SAMPLE_STRATEGY_RESULT` を実レスポンスに差し替え。ローディング/エラー処理 | 実戦略が表示される | 🔵 |
| NA-3 | NA | 動画アップロード(撮影→backend→Gemini)。プレミアム課金導線(別途要件) | 現地戦略が通しで動く | 🔵 |

---

## 進め方メモ

- **GitHub Issue が使えない**(MCP トークン narikei-74 が両リポにアクセス不可・`gh` 未導入。`findings/2026-05-29-github-mcp-account-mismatch-pr.md`)。本ファイルを暫定タスクボードにし、Issue 化はアクセス解決後。
- 着手は **Phase 1(既存移行)から**。分析の回帰を防ぐため BE-8(テスト)を早めに用意。
- backend は現在 `main`。着手時に `develop` 起点でブランチを切る(§6.1)。
- 課金(プレミアム)は本サービス初の決済 → 別イニシアチブ級。MVP は利用回数制限を先行。
