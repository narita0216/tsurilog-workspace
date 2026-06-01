# ADR-0007: 環境データは天気/海象を Open-Meteo に移行・潮は WWO 据え置き・水深は OpenTopoData/GMRT

> **改訂 2026-05-29:** 当初「WWO 全廃 → Open-Meteo + tide736 + 海しる」を検討したが、実検証で
> **海しるは潮汐がリンク型(数値なし)・地形も綺麗な点APIでない**ため不採用、**tide736 は港コード指定**で
> 磯/河口に不向き → **潮は WWO 据え置き**、**水深は OpenTopoData(GEBCO)/GMRT** に確定。以下は最終内容。

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** narita
- **Tags:** env-data, external-api, cost, ai-strategy, migration

## Context

釣りログの環境データは現状ほぼ **WWO(World Weather Online)一本**(`app/Services/GetEnvData.php` →
`EnvCache`、mesh5km×date×hour)で、天気/波/水温/風/潮位を取得。潮回り(tid_type)だけ `tide736.net`。
地形/水深は未取得(`findings/2026-05-29-env-data-wwo-only-no-terrain.md`)。

問題:
- **WWO の海象品質に疑問**(PoC: 有義波高 < うねり・周期粗い・水温ズレ。`assessment/external-apis-ai-strategy.md`)。
- **forecast の長期キャッシュで劣化**(1週間前予報が当日まで残る。再取得しない実装)。
- AI戦略機能では**生の精密値と地形**が必要だが、既存は区分値(マスタID)で地形なし。
- コスト制約あり(大きな予算は割けない)。

新規 AI 機能だけでなく**既存の環境データ取得・分析ごと品質を上げたい**というのが意思。

## Options

### Option A: WWO を全廃し Open-Meteo + tide736.net + 海しる(採用)
- 天気/風/気温/波/水温 = **Open-Meteo**(Standard $29/月・100万回・Marine+Weather 込み・**JMA モデル**で日本高品質)。
- 潮(潮回り/潮位カーブ/満干) = **tide736.net**(無料・日本736港・決定論的)。
- 水深/地形 = **海しる(MSIL)**(無料・公式)。
- **Pros:** 月 $29 で天気+海象を全網羅(予算内)。日本は JMA モデルで高品質。潮は決定論的でキャッシュ劣化なし。WWO 品質問題を解消。地形を新規獲得。
- **Cons:** 既存 `GetEnvData`/`EnvCache`/マスタバケット化のリファクタが必要(分析に影響、要テスト)。tide736 は個人運営(可用性リスク)→ 長期キャッシュ/事前計算で吸収。Open-Meteo 商用は表記リンク必須・海しるはクレジット表記+登録必須。

### Option B: WWO 据え置き、AI戦略だけ新ソース
- **Pros:** 既存に手を入れず低リスク。
- **Cons:** WWO 品質問題が既存分析に残る。env データ取得経路が二重化。ユーザー意思(既存も直す)に反する。

### Option C: 現状維持(WWO のまま)
- **Cons:** 品質問題・キャッシュ劣化・地形なしが残る。却下。

## Decision

**最終(2026-05-29 実検証後):**
- **天気/風/気温/波/水温 = Open-Meteo**(Standard $29/月・JMAモデル・lat/lng)。既存 env data ごと WWO から移行。
- **潮の動き = WWO 据え置き**(lat/lng・既存実装流用。潮の動きは天文計算でタイミング実用十分)。
- **水深/地形 = OpenTopoData(GEBCO2020)本命 / GMRT 代替**(lat/lng・無料・JSON)。新規。
- **不採用:** 海しる(潮汐リンク型で数値なし・地形も点API不適)、tide736(港コード指定で磯/河口に不向き)、NOAA NCEI(点深度に不適)。

WWO は**潮の動きのみ**に縮小(品質懸念のある天気/波は Open-Meteo へ)。

## Consequences

- **得るもの:** 日本で高品質(JMAモデル)・低コスト($29/月)・地形データ獲得・WWO品質問題の解消。
- **失うもの:** WWO の「1ソースで全部」の手軽さ。tide736 の可用性保証(→キャッシュで吸収)。
- **新たに発生する作業:**
  1. backend `GetEnvData` の天気/風/気温/波/水温を **Open-Meteo**(forecast + marine + archive)に書き換え。**潮の動きは WWO のまま残す**。
  2. 天気コードのマッピングを **WMO コード基準**に再実装。風 m/s・波 m のバケット閾値は流用。
  3. `EnvCache` に **forecast 失効(TTL)**を導入(対象日に近づいたら再取得。潮は対象外)。
  4. 既存の**マスタバケット化**を維持しつつ、AI戦略用に**生値**も保持(設計判断)。
  5. **水深 = OpenTopoData(GEBCO)/GMRT** を新規追加(lat/lng・キャッシュ)。
  6. Open-Meteo 商用プラン契約(表記リンク)。API キーは backend `.env`/Secrets(デフォルト値に書かない・ADR-0006)。
  7. 分析(`GetAnalysis*`)が壊れないことを Feature テストで担保。
- **後戻り可能性:** costly to undo(分析が依存するため移行は段階的に・テスト必須)。

## Related
- ADR-0006(AI は Laravel 内・secrets 集約)
- `assessment/external-apis-ai-strategy.md`(PoC・料金)
- `findings/2026-05-29-env-data-wwo-only-no-terrain.md`
- `initiatives/ai-strategy-feature.md`
- ツール: `tools/marine-api-poc.mjs`
