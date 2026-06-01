# Assessment — AI戦略機能の外部API選定(2026-05-29)

AI戦略機能(`initiatives/ai-strategy-feature.md`)で使う外部 API を「日本沿岸カバレッジ・料金・商用可否・実装容易さ」で調査したスナップショット。料金は 2026-05 時点。最新は各公式を要確認。

---

## 結論(推奨スタック)

| 役割 | 推奨 | 理由 |
|---|---|---|
| 天気・波高・うねり・水温・風 | **Open-Meteo**(商用プラン) | 品質良好(PoC)・API 単純。有料アプリは Standard+ 必須(料金は要問い合わせ)・CC BY 表記。forecast は対象日近くで再取得 |
| 潮(潮回り・潮位カーブ・満干) | **tide736.net** | 無料・日本特化・既に一部統合済み。潮は決定論的でキャッシュ劣化なし。**WWO 不要に** |
| 水深・海底地形(日本沿岸) | **海しる(MSIL)公開API** | 公式・無料・地形は実質これ一択。要登録 + クレジット表記 |
| 動画解析(現地戦略) | **Gemini 2.5 Flash** | 動画マルチモーダル・安価($0.30/$2.50 per 1M)|
| 戦略立案(メイン) | **Claude Sonnet 4.6** | 推論品質。$3/$15 per 1M |
| 簡易判断 | **Claude Haiku 4.5** | $1/$5 per 1M。軽処理を振り分け |
| コスト最適化 | **Prompt Caching** | キャッシュ読取 0.1x = 反復入力 90%削減 |

> **この構成で WWO を完全に外せる**(天気/波=Open-Meteo、潮=tide736.net、地形=海しる)。WWO の品質懸念(PoC)を回避できる。
> 適用範囲(AI戦略のみ / 既存 env data も移行)は要決定 → Open Questions。

---

## 1. 水深・地形・海象(日本沿岸)

### 海しる(MSIL)公開API — **本命** `portal.msil.go.jp`
海上保安庁の海洋状況表示システム。約100以上の API。利用登録でサブスクキー発行、試用キーも公開、OAS 定義あり。

取得できる項目(本機能に効くもの):
- **等深線**(水深グリッドから生成)
- **海底地形名**(日本周辺・日英)
- ⚠️ **潮汐推算は「リンク型」**: エンドポイント `api.msil.go.jp/oceanography/tide/prediction/links/v2` の
  スキーマは `tide_prediction_links_geojson` = **海保の潮汐推算"地点"への外部リンクの GeoJSON**(地点/港単位)。
  **潮位の数値(毎時潮位・満干時刻)を API で返さない。** よって**潮の動きのデータ源には使えない**(2026-05-29 確認・試用キーで 404)。
  → 潮の動きを数値で取れるのは **WWO(lat/lng・品質疑問)か tide736(港・JMA級・無料)** のみ。海しるは**地形/水深専用**と位置づける。
- **潮流推算**(日本沿岸の潮流)
- **水温**(連続観測点・外部リンク形式)
- ❌ **波高は API 無し**

**ライセンス/制約(`portal.msil.go.jp/agreement`):**
- 料金記載なし(= 実質無料と思われる)。
- **商用利用の明示なし**だが「アプリケーションの作成・運営・サービス提供」を想定した規約 → 要問い合わせ/登録時確認。
- **クレジット表記が必須**(「海しるAPIを利用して取得した情報をもとに作成。内容は海保が保証するものではない」旨をアプリ内に明示)。
- 負荷に応じた**アクセス制限あり**(具体値非公開)→ 既存の env_cache / mesh 同様キャッシュ前提で叩く(CLAUDE.md §7 リスク#4)。

### NOAA NCEI bathymetry — **フォールバック/海外用** `ncei.noaa.gov`
- グローバルな水深データ。REST は Crowbar API / CSB Data Extract API(soundings のメタdata・抽出が主)で、「緯度経度→水深」の素直な点問い合わせ用途には噛み合いにくい。
- 無料・制限なしだが、**日本沿岸の解像度・使い勝手は MSIL に劣る**見込み。海外対応や MSIL 障害時の保険として位置づけ。

### 波高の供給源(MSIL に無いため別途必須)
有料アプリ(プレミアム¥500/月)なので**商用ライセンス**が論点:
- **WWO(World Weather Online)Marine**: 要件定義書の当初案。波高・うねり・潮汐・海面/水温・気象を網羅。有料(無料枠あり)。1ソースで広く賄える。
- **Open-Meteo Marine**: 波高/うねり/周期/向きを無料・キー不要で提供。ただし**無料は非商用**。商用は別途有料プラン要確認(比較的安価)。
- **Stormglass**: 波高・水温・潮汐を統合提供。本番は有料。
- (将来)**Yahoo天気API**: 要件の移行候補。日本特化だが海象 API 提供範囲は要確認。

> 方針案: **MSIL(潮汐・水深・水温)+ 波高/気象予報を 1 つの海象API**で補完。波高ソースは商用ライセンスとコストで決定(下記 Open Question)。

---

## 2. 生成AI(Claude / Gemini)

### Gemini 2.5 Flash(動画解析)
- $0.30 / 1M 入力、$2.50 / 1M 出力。マルチモーダル(text/image/audio/video)。音声は 3.33x。
- 現地動画(最大30秒想定)の解析に。Laravel からは HTTP(REST)で呼ぶ(File API で動画アップロード→解析)。

### Claude(戦略立案)— ADR-0006 で Laravel 内 HTTP 呼び出しに決定
- **Sonnet 4.6**: $3 / $15(in/out)。メインの戦略生成。
- **Haiku 4.5**: $1 / $5。簡易判断・短い回答を振り分け(要件のコスト最適化)。
- **Prompt Caching**: cache write 1.25x / cache read 0.1x。釣り専門知識のシステムプロンプトをキャッシュ → 反復入力を最大 90%削減(要件どおり実現可能)。
- Batch API は 50%引きだが**非同期(最大24h)**なので、リアルタイム戦略には不適。事前戦略の先行生成など使えるケースがあれば検討。
- Sonnet 4.6 / Opus は 1M コンテキスト対応(本機能は直近5往復のみ送信方針なので不要)。

---

## Open Questions(要決定)

1. **波高/気象予報の API**: WWO / Open-Meteo 商用 / Stormglass のどれか。商用ライセンス可否とコストで決定。MVP は WWO(網羅性)or Open-Meteo 商用(安価)が有力。
2. **潮汐の供給源**: 既存の潮/潮位 API を維持 vs MSIL 潮汐推算に統一。重複するので方針を決める。
3. **海しる商用利用の可否**: 登録時/問い合わせで確認。クレジット表記をアプリ内のどこに出すか。
4. **Gemini の動画アップロード経路**: native→backend→Gemini(secrets 集約・推奨)。動画サイズ/長さ上限と保持/削除ポリシー(initiative OQ5)。

---

## PoC(波高/海象APIの実測比較)

決定方針: **PoC で実測してから波高/気象 API を確定**(2026-05-29)。比較ツール:
`harness-engineering/tools/marine-api-poc.mjs`(Open-Meteo / WWO / Stormglass を同地点で横並び)。

```bash
# キー無しでも Open-Meteo は動く(評価用)
node harness-engineering/tools/marine-api-poc.mjs 33.47 135.78   # 串本沖
# WWO / Stormglass はキーを env で渡すと比較対象に加わる
WWO_API_KEY=xxx STORMGLASS_API_KEY=yyy node harness-engineering/tools/marine-api-poc.mjs 33.47 135.78
```

### 既存実装の実態(2026-05-29 コード確認)
- backend `app/Services/GetEnvData.php` が **環境データを WWO のみ**から取得(`marine.ashx` 現在/予報 + `past-marine.ashx` 過去、`tide=yes`/`lang=ja`/`tp=1`)。
- 取得項目: 潮汐 / 天気 / 気温 / 水温(`waterTemp_C`)/ 風速 / 波高(`sigHeight_m`)を時間ごと → `EnvCache`(mesh 5km × date × hour)にキャッシュ。
- 値は**マスタID にバケット化**して保存(`waveHeightMaster` 等)= 生の数値でなく区分値。**AI戦略は生の精密値が欲しい**ので、ここは別取得 or 生値保持の検討が要る。
- **地形/水深は両リポで未取得**(参照ゼロ)。AI戦略で初導入。
- ⚠️ WWO キーが `config/worldweatheronlineapi.php` の `env()` デフォルトに**ハードコード**(リポに平文)→ finding 参照。

### 実測比較(2026-05-29・串本沖 33.47,135.78・先頭時刻)
| ソース | 波高 | うねり | 周期 | 向き | 水温 | 潮汐 |
|---|---|---|---|---|---|---|
| Open-Meteo | 1.78m | 1.46m | 10.2s | 168° | 24.5℃ | なし(海しるで補完) |
| WWO | **0.9m** | **1.8m** | **6s** | 170° | 24℃ | あり(LOW 3:13 0.42m) |
| Stormglass | 1.22m | 1.17m | 9.08s | 129° | 25.6℃ | あり(low -0.8m) |

2地点目(相模湾 35.05,139.65):
| ソース | 波高 | うねり | 周期 | 向き | 水温 |
|---|---|---|---|---|---|
| Open-Meteo | 0.96m | 0.9m | 10.1s | 165° | 23.1℃ |
| WWO | 1.1m | 1.1m | 11.5s | 195° | **19℃** |
| Stormglass | 1.07m | 0.77m | 5.69s | 191° | 21.9℃ |

> **所見(2地点の総合):** 「どれかが明確に正確」とは言えない。串本では WWO 波高が不自然(波高<うねり・周期6s)、相模湾では WWO 水温(19℃)が他(22〜23℃)より低くズレ、Stormglass 周期も地点で 9.08s↔5.69s と大きく変動。**ソース間の差は無視できないが、地上真値が無いので精度での一本化は不可。** → 選定は**精度でなく「統合コスト・ライセンス・カバレッジ」で判断**するのが妥当。
>
> - **WWO**: 既に backend に統合済み・課金済み・潮汐/波/水温/天気を1本で網羅。最小摩擦。データ品質に疑問は残る。
> - **海しる**: 無料・公式・日本沿岸の水深/地形/潮汐/水温。**波高なし**。地形は実質これ一択。
> - **Open-Meteo**: 波/水温は良好・無料(評価)。**有料アプリは商用ライセンス要確認**・**潮汐なし**・新規統合。
> - **Stormglass**: 波/潮汐/水温を1本。無料枠が極小(本番は有料)・新規統合。
>
> **推奨(MVP):** 波高/気象は**既存 WWO を流用**(統合済み・追加コストなし)+ **地形/水深は海しる新規導入**(+ 潮汐/水温も海しるに寄せる余地)。品質改善(波の Open-Meteo/Stormglass 化)は後続で再評価。

要取得キー(ユーザー作業):
- **海しる(MSIL)**: `portal.msil.go.jp` で利用登録 → サブスクキー(本命・水深/潮汐/水温)
- **WWO**: `worldweatheronline.com` 無料登録 → キー
- **Stormglass**: `stormglass.io` 無料登録 → キー

## Sources
- 海しる公開API: https://portal.msil.go.jp/ , https://portal.msil.go.jp/msil-api-list , https://portal.msil.go.jp/agreement
- NOAA NCEI bathymetry: https://www.ncei.noaa.gov/products/bathymetry
- WWO Marine: https://www.worldweatheronline.com/weather-api/api/marine-weather-api.aspx
- Open-Meteo Marine / Licence: https://open-meteo.com/en/docs/marine-weather-api , https://open-meteo.com/en/licence
- Stormglass: https://stormglass.io/marine-weather/
- Gemini pricing: https://ai.google.dev/gemini-api/docs/pricing
- Claude pricing: https://platform.claude.com/docs/en/about-claude/pricing
