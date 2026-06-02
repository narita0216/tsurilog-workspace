# Initiative: AI戦略作成機能(事前戦略 / 現地戦略)

- **Status:** 🟡 進行中(要件定義済み・選定/構築フェーズ)
- **Owner:** narita
- **Date started:** 2026-05-29
- **Related:** ADR-0002(API コントラクト) / 新規 ADR 予定(AI実行アーキテクチャ・外部API選定)

## なぜやるか(目的)

釣り人に「最強のインストラクター」を提供する。釣りログの釣行 DB・環境データと生成 AI を組み合わせ、
**事前戦略**(釣行前に最適戦略を立案)と**現地戦略**(現地動画+リアルタイム環境を踏まえた戦略)を出力する。
事前戦略を作っていれば現地戦略作成時に自動読込し、「予測 vs 実態」を照合した高精度戦略を返す。

理想状態:対象魚種・釣り場・日時・釣り方を入れると、総合判断 / 狙い目時間帯 / おすすめポイント /
攻め方手順 / 推奨タックル / 注意点を含む実用的な戦略がアプリ内で受け取れる。

## 2 機能の業務フロー

### 事前戦略
1. 対象魚種を入力 → 2. 釣り場をマップ長押しで選択(緯度経度)→ 3. 日時入力 → 4. 釣り方入力 → 5. 自由入力(任意)
6. AI が釣りログ API 経由で情報収集 → 7. 分析・戦略作成(Claude)→ 8. レスポンス

### 現地戦略
1. 対象魚種 → 2. 釣り方 → 3. 現地動画を撮影 → 4. 自由入力(任意)
5. Gemini が動画解析(透明度/濁り/海面/周辺地形)→ Claude に共有
6. AI が釣りログ API + リアルタイム環境を収集 → 7. 分析・戦略作成(Claude)→ 8. レスポンス
- 事前戦略があれば自動読込して照合。なくても作成可。

## 技術スタック(要件案)

| 役割 | 技術 |
|---|---|
| 動画解析 | Gemini API(現地戦略のみ) |
| 戦略立案(メイン推論) | Claude API(Sonnet) |
| 簡易判断 | Claude API(Haiku) |
| 地形データ(水深/地形) | NOAA / 海上保安庁 API |
| 天気・海象 | WWO API(将来 Yahoo 天気 API 検討)+ 既存の潮・潮位 API |

### コスト最適化方針
- **Prompt Caching**: 釣り専門知識のシステムプロンプトをキャッシュ(`cache_control`)→ 約90%削減
- **Haiku/Sonnet 自動振り分け**: 軽い処理は Haiku、複雑な戦略は Sonnet
- **会話履歴**: API へは直近5往復のみ送信。全履歴は DB 保存

### 利用制限・課金
| プラン | 1日 | 料金 |
|---|---|---|
| 無料 | 3回/日 | ¥0 |
| プレミアム | 10回/日 | 月額¥500 |

## ゴール / 完了条件(ドラフト)

- [ ] 外部 API(Claude / Gemini / WWO / NOAA・海保)の選定とキー取得・疎通確認(PoC)
- [ ] AI 実行アーキテクチャ確定(Laravel 内 or 別サービス。secrets はサーバ側。native は backend 経由のみ)
- [ ] backend: AI戦略エンドポイント群 + DB(戦略・会話履歴・利用回数)+ Prompt Caching + モデル振り分け + レート制限
- [ ] backend: 外部 API 連携(WWO / NOAA・海保 / 既存潮汐)と動画解析連携(Gemini)
- [ ] native: 事前戦略 UI(マップ長押し点選択)・現地戦略 UI(動画撮影)・結果表示
- [ ] API コントラクト 3 点整合(routes / native / openapi、`/contract-check` green)
- [ ] 課金(プレミアム)導線
- [ ] (機能完成後)特許検討:Gemini動画解析→Claude戦略立案のフロー + 釣りログDB×環境×AI の構成

## タスク分解(実装)

→ **`ai-strategy-tasks.md`**(Phase1 既存移行 / Phase2 AI backend / Phase3 native。GitHub Issue 下書き兼ボード)

## 進め方(計画・暫定)

> 詳細な順序とフェーズ分けは「要すり合わせ論点」確定後に更新する。

- **フェーズ0(現在)**: イニシアチブ化・ブランチ運用の明文化・アーキ/選定の意思決定すり合わせ。
- **フェーズ1**: 外部 API 選定 + PoC(Claude/Gemini/地形/天気の疎通)。ADR 化。
- **フェーズ2(フェーズ1と並行可)**: native モック画面(スタブデータ)。要件・出力フォーマットを画面で固める。
- **フェーズ3**: backend エンドポイント + DB + AI オーケストレーション + レート制限。
- **フェーズ4**: native を実 API に接続。課金導線。`/contract-check` で整合確認。

## 決定済み

- ✅ **AI 実行場所(2026-05-29)**: 既存 Laravel backend 内で Claude/Gemini を呼ぶ(ADR-0006)。AI-2 = Laravel。
- ✅ **認証(AI-3 再定義)**: 既存 Bearer `auth.apitoken` を流用 → **JWT 不要**(別サービスを立てないため)。
- ✅ **着手順(2026-05-29)**: native モック画面と外部 API 選定/PoC を**並行**で進める。両者の知見で backend 設計を確定。

## 要すり合わせ論点(Open Questions)

1. ~~AI 実行場所~~ → ADR-0006 で決定。
2. ~~認証(JWT)~~ → 既存 Bearer 流用で決定。
3. **secrets 管理**: API キーは backend `.env` のみ。native には絶対置かない(native→backend→AI の一方向)。
4. **外部 API の確度**: 海上保安庁の水深/地形 API は提供形態・利用規約・日本沿岸カバレッジ要調査。
   WWO の水温/波高の精度と料金、Yahoo 天気移行の条件。
5. **動画の扱い**: 現地動画のサイズ・長さ上限、アップロード経路(backend 経由 or 直接 Gemini)、保持/削除ポリシー。
   - ✅ **カメラ有効化済み(2026-05-29)**: app.json の expo-image-picker に `cameraPermission` /
     `microphonePermission` を設定し、現地戦略はカメラ起動の動画撮影(`launchCameraAsync` +
     `requestCameraPermissionsAsync`)に対応。**反映には dev client の再ビルドが必要**
     (`eas build --profile development` or `expo run:ios`)。
6. **レスポンス形**: 既存 `is_success` / `error_message` 慣習に合わせる(CLAUDE.md §4)。戦略本文は構造化 JSON か Markdown か。
7. **課金基盤**: 既存に決済はない(CLAUDE.md §2「決済は存在しない」)。プレミアム¥500/月をどう実現するか
   (App内課金 RevenueCat / StoreKit + Google Play Billing 等)は大きな別決定。MVP では利用回数制限のみ先行も可。

## 進捗ログ

- **2026-05-29:** 要件定義書を受領しイニシアチブ化。CLAUDE.md §6.1 に「最新 develop 起点・両リポ・develop への PR」の実装着手手順を明文化。アーキ/選定の Open Questions を整理。
- **2026-05-29:** native モック完成(`feature/ai-strategy-mock`、事前/現地+結果表示)。dev client 再ビルドで実機確認OK(カメラ撮影含む)。
- **2026-05-29:** 外部API選定の調査完了 → `assessment/external-apis-ai-strategy.md`。日本沿岸の水深/地形/潮汐/水温は**海しる(MSIL)**が本命(無料・要登録・クレジット表記・波高は無し)。動画=**Gemini 2.5 Flash**、戦略=**Claude Sonnet/Haiku** + Prompt Caching。残る決定は**波高/気象予報の API**(商用ライセンス論点)と潮汐ソースの統一。
- **2026-05-29:** 波高/海象APIは「PoCで実測してから決める」方針に。比較ツール `tools/marine-api-poc.mjs` を作成。
- **2026-05-29:** キー受領し PoC 完走(WWO/Open-Meteo/Stormglass を串本沖・相模湾で実測)。WWO は品質懸念(波高<うねり・水温ズレ)。精度での一本化は不可。
- **2026-05-29:** 既存潮汐を調査 → 潮回りは `tide736.net`(WWO でない)。tide736.net は潮位カーブ/満干も返し**潮を完全に賄える**(決定論的でキャッシュ劣化なし)。forecast の長期キャッシュが品質劣化要因と判明。
- **2026-05-29:** Open-Meteo の品質/料金確認 — Standard **$29/月・Marine+Weather込み・JMAモデル**で日本高品質(東京で実測OK)。
- **2026-05-29:** 海しる/tide736 を実検証し**両方不採用**に転換。海しる潮汐は**リンク型 GeoJSON で数値なし**・地形も点API不適。tide736 は港コード指定で磯/河口に不向き。→ **最終確定(ADR-0007 改訂)**: 天気/風/気温/波/水温=**Open-Meteo(JMA)**、潮の動き=**WWO 据え置き**(潮専用に縮小)、水深=**OpenTopoData(GEBCO2020)/GMRT**(lat/lng・無料、実測で水深取得確認)。全部 lat/lng・港コードゼロ・追加コストは $29 のみ。
- **2026-05-29:** タスク分解を最終構成に更新(`ai-strategy-tasks.md`)。**workspace リポに GitHub Issue 作成**(narita0216 PAT)— エピック #1 + Phase1 BE-1〜BE-8(#2〜#9)。
- **2026-06-02:** **Phase 2 縦スライス着手・主要部完成**(AI戦略 backend)。AI クライアント基盤(`AnthropicClient`=Haiku 4.5・`GeminiClient`=Gemini 2.5 Flash、**実 API 疎通確認済み**・モデルは env で差し替え可)。DB(ai_strategies/会話履歴/利用回数)・`StrategyService`(情報収集+Claude生成+JSON解析)・エンドポイント(pre-trip/on-site/history)・利用制限(無料3/プレミアム10)を実装。phpunit **193 tests 全 green**。commit `9209c4b`(+ AI基盤 `5fb3551`)。残: BE-12(大容量動画 File API + native アップロード)、BE-16(openapi/contract)、on-site テスト、Phase 3(native 実接続)。
  - **ブランチ構成(スタック):** `feature/ai-strategy-api` は **`feature/env-data-open-meteo`(Phase 1)を起点**にしている(Phase 1 が develop 未マージのため)。**owner の PR は Phase 1 → Phase 2 の順**で。Phase 1 が develop にマージされたら Phase 2 PR の base は develop。
- **2026-05-29:** **Phase 1(env-data 移行)backend 完成**。backend をローカル Docker で起動しテスト確立。BE-1〜BE-8 実装(`OpenMeteoClient`/`GetEnvData` 書換・WMOマッピング・生値カラム・forecast TTL・`DepthService`・WWOキー既定値削除)+ 検証テスト(`GetEnvDataServiceTest`/`DepthServiceTest`)。GD を Dockerfile に追加。**phpunit 186 tests 全 green**。6コミット(`dc8b7fd`〜`1e31b7f`)を `feature/env-data-open-meteo` にローカル積み(push/PR はオーナー対応)。残: WWO キーのローテーション(オーナー)。次は Phase 2(AI戦略 backend)— Claude/Gemini キーが要る。

## 落とし穴・メモ

- native に AI/外部 API キーを置かない(漏洩リスク)。必ず backend 経由。
- 課金は本サービス初の決済機能 → ストア審査・基盤選定の影響大。要件として重い。
- 特許の観点から、Gemini動画解析→Claude戦略立案のフローと DB×環境×AI 構成は実装ログを残す価値あり。
- (発見は `findings/` にも残す)
