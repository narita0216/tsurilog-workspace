# 既存の環境データは WWO 一本・地形は未取得・WWO キーがリポに平文

- **Date:** 2026-05-29
- **Repo:** tsurilog-backend
- **Tags:** env-data, external-api, wwo, security, ai-strategy

## 事実(コード確認済み)

釣りログの環境データ取得は **ほぼ WWO 一本**だが、潮の一部は別ソース:
- `app/Services/GetEnvData.php` が **WWO**(`marine.ashx` 現在/予報 + `past-marine.ashx` 過去、`tide=yes`/`lang=ja`/`tp=1`)から
  時間ごとに抽出 → `EnvCache`(`mesh_5km_id` × `date` × `hour`):
  - **潮位の動き**(`tides` → tidAction)、天気(`weatherCode`)、気温(`tempC`)、
    **水温(`waterTemp_C`)**、風速(`windspeedKmph`)、**波高(`sigHeight_m`)**
- **潮回り(大潮/中潮/小潮 = tid_type)だけは `tide736.net`**(`app/Services/FetchTidTypeService.php`、`app:fetch-tid-type` バッチ)。WWO ではない。
- 保存は**マスタIDにバケット化**(`weatherMaster`/`windSpeedMaster`/`waveHeightMaster`/`tidTypeMaster`/`tidActionMaster`)= 生値でなく区分値。
- **地形・水深は両リポに参照ゼロ**(`depth`/`bathymetry`/`海底`/`等深`/`noaa`/`msil` いずれもヒットなし)。

### 重要: tide736.net は潮を完全に賄える(WWO 不要)
`tide736.net/api/get_tide.php`(pc/hc=港コード)は無料・日本特化で、実測(2026-06-01)で以下を返す:
- 潮回り(`moon.title`)、満潮/干潮の時刻+潮位(`flood`/`edd`)、**20分刻みの潮位カーブ(`tide[].cm`)**。
- **潮汐は天文ベースで決定論的** → 予報のように古くならず、長期キャッシュしても劣化しない。
→ 潮位の動き(現状 WWO)も tide736.net で代替可能。**潮は WWO 不要**。

### 重要: forecast の長期キャッシュが品質を落とす
`EnvCache` は一度キャッシュすると再取得しない実装。天気/波は**予報**なので、1週間前に取った予報が
そのまま残ると当日精度より悪い(前日予報 > 1週間前予報)。**forecast 系は target 日に近づいたら再取得**
(TTL/失効)する設計が要る。**潮は決定論的なので対象外**。

## なぜ重要か(AI戦略機能への影響)

1. **「天気/潮汐/波高/水温=全部WWO」**。WWO の海象は粗い疑いがある(PoC: 有義波高 < うねり、周期6s。
   `assessment/external-apis-ai-strategy.md` の実測比較)。AI戦略の精度に直結するので波高/海象ソースは PoC で見直す。
2. **既存は区分値(バケット)で保存**。AI戦略は生の精密値(例: 波高 1.78m、水温 24.5℃)が欲しい →
   既存 `EnvCache` をそのまま使うか、AI用に生値を別取得/別保持するか設計判断が要る。
3. **地形/水深は新規**。海しる(MSIL)で初導入する(`assessment/...`)。
4. ⚠️ **セキュリティ: WWO の API キーが `config/worldweatheronlineapi.php` の `env('WWO_API_KEY', '<デフォルト値>')`
   の第2引数(デフォルト)にハードコード**されている = リポに平文で残る。`.env` 未設定でも動くが、
   キーが履歴に露出している。AI戦略で新たに足す Claude/Gemini/海しる/波高 API のキーは
   **デフォルト値に書かず `.env` / EAS Secrets 等で注入**する(native には置かない・ADR-0006)。
   既存 WWO キーもローテーション + デフォルト削除を検討。

## どうするか

- AI戦略の環境データ設計: 「既存 EnvCache(区分値・WWO)」と「AI用の生値(海しる + 波高API)」の関係を decisions で整理。
- 波高/海象ソースは PoC 比較(`tools/marine-api-poc.mjs`)で確定 → ADR。
- 新規 API キーはコードのデフォルト値に書かない運用を徹底(本 finding を参照)。

## 関連
- `assessment/external-apis-ai-strategy.md`(選定・PoC)
- `initiatives/ai-strategy-feature.md`
- ADR-0006(AI は Laravel 内・secrets は backend に集約)
- CLAUDE.md §2(env data)/ §7 リスク#4
