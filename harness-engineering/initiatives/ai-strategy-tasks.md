# AI戦略機能 — 実装タスク分解(GitHub Issue 下書き兼タスクボード)

`initiatives/ai-strategy-feature.md` の実装タスク。GitHub Issue が使えない間はここを正本のタスクボードとする
(各タスクはそのまま Issue 本文に転記できる粒度)。ADR-0006 / 0007 準拠。

- **Status 凡例:** 🔵未着手 / 🟡進行中 / 🟢完了 / ⛔ブロック
- **対象リポ:** BE=tsurilog-backend / NA=tsurilog-native

---

## Phase 1: 環境データ移行 — 天気/海象=Open-Meteo・潮=WWO据え置き・水深=OpenTopoData/GMRT(ADR-0007)

> 既存分析が依存するため**段階的 + Feature テスト必須**。`develop` 起点 `feature/env-data-open-meteo`。
> 採用: Open-Meteo(天気/風/気温/波/水温)・WWO(潮の動きのみ据え置き)・OpenTopoData(水深)。海しる/tide736 は不採用。
>
> **GitHub Issue:** エピック [#1](https://github.com/narita0216/tsurilog-workspace/issues/1) / BE-1〜BE-8 = workspace Issue #2〜#9。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| BE-1 | BE | Open-Meteo クライアント追加(forecast=天気/風/気温、marine=波/水温、archive=過去)。設定は `config/openmeteo.php`、キーは `.env`(デフォルト値に書かない・ADR-0006) | lat/lng で生値取得できる単体確認 | 🟡 コード実装+構文OK(`OpenMeteoClient`)。Laravel 起動での疎通確認は Docker 環境で要実施。ブランチ `feature/env-data-open-meteo` |
| BE-2 | BE | `GetEnvData` 書き換え: 天気/風/気温/波/水温を Open-Meteo に。**潮の動き(`calculateTideAction`)は WWO のまま残す**(WWO は潮専用に縮小) | 既存 `index()` シグネチャ維持で EnvCache を生成 | 🔵 |
| BE-3 | BE | マッピング再実装: **WMO 天気コード**→`weathers`(新 `convertWmoCodeToWeatherId`)、風は `windspeed_unit=ms` 取得でバケット閾値流用、波高 m バケットも流用 | 既存マスタID体系と整合(分析が壊れない) | 🔵 |
| BE-4 | BE | 水深取得サービス新規: **OpenTopoData(GEBCO2020)** を lat/lng で叩き水深を取得・キャッシュ(高解像度が要れば GMRT 併用)。無料・キー不要 | 任意地点の水深(m)が取得できる | 🔵 |
| BE-5 | BE | `EnvCache` に**生値カラム追加**(波高m・風速m/s・水温℃・水深m 等、additive migration)+ forecast メタ(`fetched_at`/`is_forecast`)。既存バケット列は分析互換のため維持 | migrate 追記式・既存列を壊さない | 🔵 |
| BE-6 | BE | **キャッシュ失効(TTL)**: forecast 行は対象日が近づいたら再取得(古い予報を使わない)。潮/水深は対象外 | 1週間前予報が当日まで残らない | 🔵 |
| BE-7 | BE | Feature テスト: `GetAnalysis*`(env_data/condition_stats/rate)+ `GetEnvData` のマッピング(HTTP モック)。移行前後で分析結果が一致 | テスト green(`/backend-check`) | 🔵 |
| BE-8 | BE | WWO の**天気/波/水温の呼び出しを除去**(潮のみ残す)+ キーのデフォルト値削除 + ローテーション。レスポンス形が変われば `/contract-check` + openapi 更新 | WWO は潮のみ・contract green | 🔵 |

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

- **GitHub Issue は workspace リポ(narita0216/tsurilog-workspace)に集約**して管理(narita0216 の PAT を curl で使用。MCP トークン narikei-74 は両コードリポにアクセス不可・`gh` 未導入)。コード固有タスクも当面は workspace に Issue を立て、本ファイルと対応させる。`findings/2026-05-29-github-mcp-account-mismatch-pr.md`。
- 着手は **Phase 1(既存移行)から**。分析の回帰を防ぐため BE-8(テスト)を早めに用意。
- backend は現在 `main`。着手時に `develop` 起点でブランチを切る(§6.1)。
- 課金(プレミアム)は本サービス初の決済 → 別イニシアチブ級。MVP は利用回数制限を先行。
