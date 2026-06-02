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
| BE-1 | BE | Open-Meteo クライアント追加(forecast=天気/風/気温、marine=波/水温、archive=過去)。設定は `config/openmeteo.php`、キーは `.env`(デフォルト値に書かない・ADR-0006) | lat/lng で生値取得できる単体確認 | 🟢 **完了・実起動検証OK**(tinker で forecast/marine 168行取得確認、2026-05-29)。ブランチ `feature/env-data-open-meteo`(commit `dc8b7fd`) |
| BE-2 | BE | `GetEnvData` 書き換え: 天気/風/気温/波/水温を Open-Meteo に。**潮の動き(`calculateTideAction`)は WWO のまま残す**(WWO は潮専用に縮小) | 既存 `index()` シグネチャ維持で EnvCache を生成 | 🟢 実装済み(commit `036cfdd`)+ BE-7 で end-to-end 検証済み |
| BE-3 | BE | マッピング再実装: **WMO 天気コード**→`weathers`(新 `convertWmoCodeToWeatherId`)、風は `windspeed_unit=ms` 取得でバケット閾値流用、波高 m バケットも流用 | 既存マスタID体系と整合(分析が壊れない) | 🟢 実装済み(`convertWmoCodeToWeatherId` + 風 m/s 直判定。commit `036cfdd`) |
| BE-4 | BE | 水深取得サービス新規: **OpenTopoData(GEBCO2020)** を lat/lng で叩き水深を取得・キャッシュ(高解像度が要れば GMRT 併用)。無料・キー不要。**水深は AI 出力の質向上の内部データのみ(アプリ非表示)→ Phase2 のプロンプト組み立て(BE-13)で利用**、env_data 表示/分析には出さない | 任意地点の水深(m)が取得できる | 🟢 `DepthService`(GEBCO2020・キャッシュ)+ テスト。commit `1e31b7f` |
| BE-5 | BE | `EnvCache` に**生値カラム追加**(波高m・風速m/s・水温℃・水深m 等、additive migration)+ forecast メタ(`fetched_at`/`is_forecast`)。既存バケット列は分析互換のため維持 | migrate 追記式・既存列を壊さない | 🟢 生値10列+forecastメタ追加。commit `46bdd69` |
| BE-6 | BE | **キャッシュ失効(TTL)**: forecast 行は対象日が近づいたら再取得(古い予報を使わない)。潮/水深は対象外 | 1週間前予報が当日まで残らない | 🟢 `isStaleForecast`(TTL=12h)+ テスト。commit `46bdd69` |
| BE-7 | BE | Feature テスト: `GetEnvData` のマッピング(HTTP モック)で移行を検証(分析テストは GetEnvData をモックのため別途) | テスト green | 🟢 `GetEnvDataServiceTest`(Open-Meteo/WWO fake・生成+TTL)。phpunit 186 green。commit `46bdd69` |
| BE-8 | BE | WWO の**天気/波/水温の呼び出しを除去**(潮のみ残す)+ キーのデフォルト値削除 + ローテーション | WWO は潮のみ・contract green | 🟢 潮のみに縮小 + キー既定値削除(commit `1e31b7f`)。env_data レスポンス形不変=contract drift なし。**WWO キーのローテーションはオーナー対応**(残) |

## Phase 2: AI戦略 backend(ADR-0006)

> `develop` 起点 `feature/ai-strategy-api`。1 EP=1 コントローラ / Request / `*ResponseService`(§8.2)。
> **GitHub Issue:** BE-10〜BE-16 = workspace Issue #10〜#16。
> **AI 基盤(クライアント)実装済み**: `AnthropicClient`(ティア差し替え可・Prompt Caching)/ `GeminiClient`(動画・テキスト)。実 API 疎通確認済み(Haiku 4.5 / Gemini 2.5 Flash)。commit `5fb3551`。モデルは env で変更可。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| BE-10 | BE | DB: `ai_strategies`・会話履歴・利用回数のマイグレーション + モデル | migrate 追記式 | 🟢 commit `9209c4b` |
| BE-11 | BE | 戦略生成サービス(`AnthropicClient`・Prompt Caching・出力フォーマット JSON 解析) | 戦略が生成できる | 🟢 `StrategyService` + システムプロンプト(`config/ai_strategy.php`)。モデルは tier で差し替え可。commit `9209c4b` |
| BE-12 | BE | Gemini 動画解析連携(小=inline_data 実装済み / 大= File API + アップロード経路) | 動画から状況要約が返る | 🟡 現地endpointで inline_data(小)対応。残: 大容量の File API + native アップロード経路。on-site テスト未追加 |
| BE-13 | BE | 情報収集の組み立て(env=GetEnvData / 水深=DepthService / 過去釣行=Record / 自由入力 / 動画 / 事前戦略照合)→ プロンプト | プロンプト生成 | 🟢 `StrategyService::buildContext`。commit `9209c4b` |
| BE-14 | BE | エンドポイント: 事前 / 現地 / 履歴(各1コントローラ)。`is_success` 慣習 | 3点整合 | 🟢 `/ai-strategy/{pre-trip,on-site,history}`。pre-trip はテスト緑。on-site テストは残 |
| BE-15 | BE | 利用制限(無料3/日・プレミアム10/日)+ 会話履歴保存 | 制限超過で拒否 | 🟢 `AiUsageService`(原子的消費)+ 会話全件保存。テスト緑。commit `9209c4b` |
| BE-16 | BE | openapi.yml 追記 + `/contract-check` green | ドリフトなし | 🟢 openapi に3エンドポイント+スキーマ追記。`/contract-check` で ai-strategy は3点整合(commit `9d52690`/native `67670d9`) |

## Phase 3: native 実接続

> モック(`feature/ai-strategy-mock`)に実接続を追加(同ブランチ)。commit `67670d9`(native)。

| ID | リポ | タスク | 受け入れ条件 | Status |
|---|---|---|---|---|
| NA-1 | NA | `api/ai-strategy/*`(1リクエスト1ファイル + 型)+ `hooks/use-ai-strategy.ts`(TanStack Query) | 型が backend と一致 | 🟢 commit `67670d9`(snake→camel mapper 付き) |
| NA-2 | NA | モックの `SAMPLE_STRATEGY_RESULT` を実レスポンスに差し替え。ローディング/エラー処理 | 実戦略が表示される | 🟢 両画面接続・上限はトースト。モック定数削除。lint+tsc green |
| NA-3 | NA | 動画アップロード(撮影→backend→Gemini)+ 現在地自動取得 | 現地戦略が通しで動く | 🟢 multipart 動画送信 + expo-location。**課金導線は別件(下記)** |

> **`/contract-check`:** ai-strategy の routes/native/openapi は**3点整合**(ドリフトなし)。stale 3 は既存の `/analysis/*` で別件。
> **実機通し確認**は backend 起動(Docker)+ dev client(カメラ反映の再ビルド済み)で要実施。
> **プレミアム課金(¥500/月)** は本サービス初の決済=別イニシアチブ級。現状は利用回数制限のみ実装(無料3/プレミアム10)。is_premium フラグの切替UI/決済基盤は未実装。

---

## 進め方メモ

- **GitHub Issue は workspace リポ(narita0216/tsurilog-workspace)に集約**して管理(narita0216 の PAT を curl で使用。MCP トークン narikei-74 は両コードリポにアクセス不可・`gh` 未導入)。コード固有タスクも当面は workspace に Issue を立て、本ファイルと対応させる。`findings/2026-05-29-github-mcp-account-mismatch-pr.md`。
- 着手は **Phase 1(既存移行)から**。分析の回帰を防ぐため BE-8(テスト)を早めに用意。
- backend は現在 `main`。着手時に `develop` 起点でブランチを切る(§6.1)。
- 課金(プレミアム)は本サービス初の決済 → 別イニシアチブ級。MVP は利用回数制限を先行。
