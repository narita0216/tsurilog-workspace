# ADR-0007: 環境データは WWO を廃止し Open-Meteo + tide736.net + 海しる に移行

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

**WWO を全廃し、天気/海象 = Open-Meteo(Standard $29/月・JMAモデル)、潮 = tide736.net、地形 = 海しる に移行する(Option A)。**
新 AI 戦略機能も既存の環境データ取得・分析もこの構成に統一する。

## Consequences

- **得るもの:** 日本で高品質(JMAモデル)・低コスト($29/月)・地形データ獲得・WWO品質問題の解消。
- **失うもの:** WWO の「1ソースで全部」の手軽さ。tide736 の可用性保証(→キャッシュで吸収)。
- **新たに発生する作業:**
  1. backend `GetEnvData` を Open-Meteo(天気/海象)+ tide736.net(潮位)に書き換え。
  2. `EnvCache` に **forecast 失効(TTL)**を導入(対象日に近づいたら再取得。潮は対象外)。
  3. 既存の**マスタバケット化**を維持しつつ、AI戦略用に**生値**も保持できるようにする(設計判断)。
  4. 海しる(MSIL)の地形/水深取得を新規追加 + 利用登録 + クレジット表記。
  5. Open-Meteo 商用プラン契約(表記リンク)。API キーは backend `.env`/Secrets(デフォルト値に書かない・ADR-0006)。
  6. 分析(`GetAnalysis*`)が壊れないことを Feature テストで担保。
- **後戻り可能性:** costly to undo(分析が依存するため移行は段階的に・テスト必須)。

## Related
- ADR-0006(AI は Laravel 内・secrets 集約)
- `assessment/external-apis-ai-strategy.md`(PoC・料金)
- `findings/2026-05-29-env-data-wwo-only-no-terrain.md`
- `initiatives/ai-strategy-feature.md`
- ツール: `tools/marine-api-poc.mjs`
