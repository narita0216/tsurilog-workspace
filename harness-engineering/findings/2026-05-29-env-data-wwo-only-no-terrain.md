# 既存の環境データは WWO 一本・地形は未取得・WWO キーがリポに平文

- **Date:** 2026-05-29
- **Repo:** tsurilog-backend
- **Tags:** env-data, external-api, wwo, security, ai-strategy

## 事実(コード確認済み)

釣りログの環境データ取得は **`app/Services/GetEnvData.php` が World Weather Online(WWO)一本**:
- `marine.ashx`(現在/予報)+ `past-marine.ashx`(過去)を `tide=yes` / `lang=ja` / `tp=1` で叩く。
- 取得項目を時間ごとに抽出 → `EnvCache`(`mesh_5km_id` × `date` × `hour`)にキャッシュ:
  - 潮汐(`tides` → tidType/tidAction)、天気(`weatherCode`)、気温(`tempC`)、
    **水温(`waterTemp_C`)**、風速(`windspeedKmph`)、**波高(`sigHeight_m`)**
- 保存は**マスタIDにバケット化**(`weatherMaster` / `windSpeedMaster` / `waveHeightMaster` / `tidTypeMaster` / `tidActionMaster`)。
  = 生の数値でなく区分値で持つ。
- **地形・水深は両リポに参照ゼロ**(`depth`/`bathymetry`/`海底`/`等深`/`noaa`/`msil` いずれもヒットなし)。

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
